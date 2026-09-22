import XCTest

@testable import Equaliser

/// Integration tests for automatic per-device preset switching.
/// Uses real instances throughout (device manager, routing coordinator, preset manager).
@MainActor
final class DevicePresetSwitchCoordinatorTests: XCTestCase {

    /// Drains main-queue deliveries scheduled via `receive(on: DispatchQueue.main)`.
    private func drainMainQueue(iterations: Int = 5) {
        for _ in 0..<iterations {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private func makeHarness() -> (coordinator: DevicePresetSwitchCoordinator, routing: AudioRoutingCoordinator, presetManager: PresetManager, mapping: DevicePresetMappingService) {
        let suiteName = "DevicePresetSwitchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let presetManager = PresetManager(storage: defaults)
        let deviceManager = DeviceManager()
        let routing = AudioRoutingCoordinator(
            deviceProvider: deviceManager,
            deviceChangeCoordinator: DeviceChangeCoordinator(deviceEnumerator: deviceManager.enumerator),
            eqConfiguration: EQConfiguration(),
            meterStore: MeterStore(),
            volumeService: DeviceVolumeService(),
            permissionService: AudioPermissionService(),
            systemDefaultObserver: SystemDefaultObserver(deviceManager: deviceManager),
            sampleRateService: DeviceSampleRateService()
        )
        let mapping = DevicePresetMappingService(storage: defaults)
        let coordinator = DevicePresetSwitchCoordinator(
            routingCoordinator: routing,
            presetManager: presetManager,
            mappingService: mapping
        )
        coordinator.autoApplyEnabledProvider = { true }
        return (coordinator, routing, presetManager, mapping)
    }

    /// Seeds `presetName` against `deviceUID` in the mapping service.
    private func record(_ mapping: DevicePresetMappingService, device uid: String, preset name: String) {
        var map = mapping.load()
        map.record(device: uid, presetName: name)
        mapping.save(map)
    }

    // MARK: - Applying on device change

    func testAppliesMappedPresetWhenDeviceChanges() {
        let h = makeHarness()
        record(h.mapping, device: "device-A", preset: "Flat")

        var applied: [String] = []
        h.coordinator.onApplyPreset = { applied.append($0) }

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()

        XCTAssertEqual(applied, ["Flat"])
    }

    func testDoesNotReapplyOnSameDeviceReassignment() {
        let h = makeHarness()
        record(h.mapping, device: "device-A", preset: "Flat")

        var applied: [String] = []
        h.coordinator.onApplyPreset = { applied.append($0) }

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()
        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()

        XCTAssertEqual(applied, ["Flat"])
    }

    func testAppliesMappedPresetPerChangingDevice() {
        let h = makeHarness()
        record(h.mapping, device: "device-A", preset: "Flat")
        record(h.mapping, device: "device-B", preset: "Flat")

        var applied: [String] = []
        h.coordinator.onApplyPreset = { applied.append($0) }

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()
        h.routing.selectedOutputDeviceID = "device-B"
        drainMainQueue()

        XCTAssertEqual(applied, ["Flat", "Flat"])
    }

    func testNoApplyWhenNoMappingExists() {
        let h = makeHarness()

        var applied: [String] = []
        h.coordinator.onApplyPreset = { applied.append($0) }

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()

        XCTAssertTrue(applied.isEmpty)
    }

    func testDisabledTogglePreventsApply() {
        let h = makeHarness()
        record(h.mapping, device: "device-A", preset: "Flat")

        h.coordinator.autoApplyEnabledProvider = { false }
        var applied: [String] = []
        h.coordinator.onApplyPreset = { applied.append($0) }

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()

        XCTAssertTrue(applied.isEmpty)
    }

    func testIgnoresDriverDeviceUID() {
        let h = makeHarness()
        record(h.mapping, device: DRIVER_DEVICE_UID, preset: "Flat")

        var applied: [String] = []
        h.coordinator.onApplyPreset = { applied.append($0) }

        h.routing.selectedOutputDeviceID = DRIVER_DEVICE_UID
        drainMainQueue()

        XCTAssertTrue(applied.isEmpty)
    }

    func testPrunesMappingWhenPresetDeleted() {
        let h = makeHarness()
        record(h.mapping, device: "device-A", preset: "Does Not Exist")

        var applied: [String] = []
        h.coordinator.onApplyPreset = { applied.append($0) }

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()

        XCTAssertTrue(applied.isEmpty)
        XCTAssertNil(h.mapping.load().presetFor(device: "device-A"))
    }

    // MARK: - Recording on preset selection

    func testRecordsPresetSelectedOnCurrentDevice() {
        let h = makeHarness()

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()

        h.presetManager.selectPreset(named: "Flat")
        drainMainQueue()

        XCTAssertEqual(h.mapping.load().presetFor(device: "device-A"), "Flat")
    }

    func testDoesNotRecordWhenNoDeviceSelected() {
        let h = makeHarness()

        h.presetManager.selectPreset(named: "Flat")
        drainMainQueue()

        XCTAssertTrue(h.mapping.load().entries.isEmpty)
    }

    func testDisabledTogglePreventsRecording() {
        let h = makeHarness()
        h.coordinator.autoApplyEnabledProvider = { false }

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()

        h.presetManager.selectPreset(named: "Flat")
        drainMainQueue()

        XCTAssertTrue(h.mapping.load().entries.isEmpty)
    }

    func testDoesNotRecordAutoAppliedPresetBackOntoSameDevice() {
        let h = makeHarness()
        record(h.mapping, device: "device-A", preset: "Flat")

        h.routing.selectedOutputDeviceID = "device-A"
        drainMainQueue()
        drainMainQueue()

        // Auto-apply flows through selectPreset internally; the mapping must stay exactly "Flat"
        XCTAssertEqual(h.mapping.load().presetFor(device: "device-A"), "Flat")
    }
}
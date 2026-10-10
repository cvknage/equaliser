import XCTest
@testable import Equaliser

@MainActor
final class EqualiserStoreTests: XCTestCase {

    func testStartupOutputPreference_restoresAndSavesBothChoices() throws {
        let suiteName = "EqualiserStoreTests.\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        let persistence = AppStatePersistence(storage: storage)

        for preference in [false, true] {
            var snapshot = AppStateSnapshot.default
            // No input selected: avoid starting an audio pipeline in this test.
            snapshot.manualModeEnabled = true
            snapshot.outputDeviceID = "speakers"
            snapshot.preferMacDefaultOnStartup = preference
            persistence.save(snapshot)

            let store = EqualiserStore(persistence: persistence)
            XCTAssertEqual(store.preferMacDefaultOnStartup, preference)

            store.preferMacDefaultOnStartup = !preference
            XCTAssertEqual(store.selectedOutputDeviceID, "speakers")
            persistence.save(store.currentSnapshot)

            let restored = try XCTUnwrap(persistence.load())
            XCTAssertEqual(restored.preferMacDefaultOnStartup, !preference)
            XCTAssertEqual(restored.outputDeviceID, "speakers")
        }
    }

    // MARK: - OutputDeviceSelection Tests

    func testDetermineAutomaticOutputDevice_preservesValidSelection() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        let result = OutputDeviceSelection.determine(
            currentSelected: "airpods",
            macDefault: DRIVER_DEVICE_UID,
            availableDevices: devices
        )

        XCTAssertEqual(result, .preserveCurrent("airpods"))
    }

    func testDetermineAutomaticOutputDevice_preservesValidSelection_whenDriverIsMacDefault() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in Speakers", transportType: 0),
            AudioDevice(id: 3, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        // User has AirPods selected, driver is macOS default (from previous crash)
        // Should preserve AirPods, not use driver or fallback
        let result = OutputDeviceSelection.determine(
            currentSelected: "airpods",
            macDefault: DRIVER_DEVICE_UID,
            availableDevices: devices
        )

        XCTAssertEqual(result, .preserveCurrent("airpods"))
    }

    func testDetermineAutomaticOutputDevice_usesMacDefault_whenNoValidSelection() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in Speakers", transportType: 0),
        ]

        // No current selection, macOS default is AirPods
        let result = OutputDeviceSelection.determine(
            currentSelected: nil,
            macDefault: "airpods",
            availableDevices: devices
        )

        XCTAssertEqual(result, .useMacDefault("airpods"))
    }

    func testDetermineAutomaticOutputDevice_usesMacDefault_whenCurrentIsDriver() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        // Current selection is driver (invalid), macOS default is AirPods
        let result = OutputDeviceSelection.determine(
            currentSelected: DRIVER_DEVICE_UID,
            macDefault: "airpods",
            availableDevices: devices
        )

        XCTAssertEqual(result, .useMacDefault("airpods"))
    }

    func testDetermineAutomaticOutputDevice_needsFallback_whenDriverIsMacDefault() {
        let devices = [
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        // Current is driver, mac default is driver, no valid devices
        let result = OutputDeviceSelection.determine(
            currentSelected: DRIVER_DEVICE_UID,
            macDefault: DRIVER_DEVICE_UID,
            availableDevices: devices
        )

        XCTAssertEqual(result, .useFallback)
    }

    func testDetermineAutomaticOutputDevice_needsFallback_whenNoValidDevices() {
        let devices = [
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
            AudioDevice(id: 2, uid: "BlackHole 2ch", name: "BlackHole 2ch", transportType: 0),
        ]

        // All devices are virtual
        let result = OutputDeviceSelection.determine(
            currentSelected: nil,
            macDefault: nil,
            availableDevices: devices
        )

        XCTAssertEqual(result, .useFallback)
    }

    func testDetermineAutomaticOutputDevice_preservesValidDevice_notInAvailableList_usesMacDefault() {
        let devices = [
            AudioDevice(id: 1, uid: "builtin", name: "Built-in Speakers", transportType: 0),
        ]

        // Current selection not in available list
        let result = OutputDeviceSelection.determine(
            currentSelected: "disconnected-device",
            macDefault: "builtin",
            availableDevices: devices
        )

        XCTAssertEqual(result, .useMacDefault("builtin"))
    }

    func testDetermineAutomaticOutputDevice_virtualDeviceSelected_usesMacDefault() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        // Driver is virtual, should use mac default
        let result = OutputDeviceSelection.determine(
            currentSelected: DRIVER_DEVICE_UID,
            macDefault: "airpods",
            availableDevices: devices
        )

        XCTAssertEqual(result, .useMacDefault("airpods"))
    }

    func testDetermineAutomaticOutputDevice_preservesCurrent_overMacDefault() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in Speakers", transportType: 0),
        ]

        let result = OutputDeviceSelection.determine(
            currentSelected: "airpods",
            macDefault: "builtin",
            availableDevices: devices
        )

        XCTAssertEqual(result, .preserveCurrent("airpods"))
    }

    func testDetermineAutomaticOutputDevice_prefersMacDefault_whenEnabled() {
        let devices = [
            AudioDevice(id: 1, uid: "speakers", name: "Built-in Speakers", transportType: 0),
            AudioDevice(id: 2, uid: "headphones", name: "Headphone Out", transportType: 0),
        ]

        let result = OutputDeviceSelection.determine(
            currentSelected: "speakers",
            macDefault: "headphones",
            availableDevices: devices,
            preferMacDefault: true
        )

        XCTAssertEqual(result, .useMacDefault("headphones"))
    }

    func testDetermineAutomaticOutputDevice_prefersMacDefault_recoversSavedOutput() {
        let devices = [
            AudioDevice(id: 1, uid: "speakers", name: "Built-in Speakers", transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        for macDefault in [nil, DRIVER_DEVICE_UID, "disconnected-device"] {
            let result = OutputDeviceSelection.determine(
                currentSelected: "speakers",
                macDefault: macDefault,
                availableDevices: devices,
                preferMacDefault: true
            )

            XCTAssertEqual(result, .preserveCurrent("speakers"))
        }
    }

    func testDetermineAutomaticOutputDevice_prefersMacDefault_allowsOtherVirtualOutputs() {
        let devices = [
            AudioDevice(id: 1, uid: "speakers", name: "Built-in Speakers", transportType: 0),
            AudioDevice(id: 2, uid: "BlackHole 2ch", name: "BlackHole 2ch", transportType: 0),
        ]

        let result = OutputDeviceSelection.determine(
            currentSelected: "speakers",
            macDefault: "BlackHole 2ch",
            availableDevices: devices,
            preferMacDefault: true
        )

        XCTAssertEqual(result, .useMacDefault("BlackHole 2ch"))
    }

    func testDetermineAutomaticOutputDevice_prefersMacDefault_withNoValidSavedOutput() {
        let devices = [
            AudioDevice(id: 1, uid: "speakers", name: "Built-in Speakers", transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        for current in [nil, DRIVER_DEVICE_UID, "disconnected-device"] {
            let result = OutputDeviceSelection.determine(
                currentSelected: current,
                macDefault: "speakers",
                availableDevices: devices,
                preferMacDefault: true
            )

            XCTAssertEqual(result, .useMacDefault("speakers"))
        }
    }

    func testDetermineAutomaticOutputDevice_prefersMacDefault_needsFallback() {
        let devices = [
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        let result = OutputDeviceSelection.determine(
            currentSelected: "disconnected-device",
            macDefault: DRIVER_DEVICE_UID,
            availableDevices: devices,
            preferMacDefault: true
        )

        XCTAssertEqual(result, .useFallback)
    }

    func testDetermineAutomaticOutputDevice_noCurrent_noMacDefault_needsFallback() {
        let devices = [
            AudioDevice(id: 1, uid: "builtin", name: "Built-in Speakers", transportType: 0),
        ]

        // No current, no mac default
        let result = OutputDeviceSelection.determine(
            currentSelected: nil,
            macDefault: nil,
            availableDevices: devices
        )

        XCTAssertEqual(result, .useFallback)
    }

    func testDetermineAutomaticOutputDevice_macDefaultNotInAvailableList_needsFallback() {
        let devices = [
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
        ]

        // Mac default is a disconnected device, no valid current
        let result = OutputDeviceSelection.determine(
            currentSelected: nil,
            macDefault: "disconnected-device",
            availableDevices: devices
        )

        XCTAssertEqual(result, .useFallback)
    }
}

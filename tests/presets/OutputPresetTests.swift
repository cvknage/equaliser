import XCTest
@testable import Equaliser

@MainActor
final class OutputPresetTests: XCTestCase {
    func testAssignmentsPersistByUIDAndAllowSeveralOutputsPerPreset() throws {
        try withPresets { manager, storage, directory in
            // Two outputs may share a display name, but have distinct UIDs.
            manager.updateOutputPreset(named: "Bass Boost", for: "usb-dac-1")
            manager.updateOutputPreset(named: "Flat", for: "usb-dac-2")
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")

            let restored = PresetManager(storage: storage, directory: directory)
            XCTAssertEqual(restored.preset(forOutputDevice: "usb-dac-1")?.metadata.name, "Bass Boost")
            XCTAssertEqual(restored.preset(forOutputDevice: "usb-dac-2")?.metadata.name, "Flat")
            XCTAssertEqual(restored.preset(forOutputDevice: "headphones")?.metadata.name, "Bass Boost")
            XCTAssertNil(restored.preset(forOutputDevice: "speakers"))
        }
    }

    func testReassignmentAndRemovalPersist() throws {
        try withPresets { manager, storage, directory in
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            manager.updateOutputPreset(named: "Flat", for: "headphones")
            XCTAssertEqual(manager.preset(forOutputDevice: "headphones")?.metadata.name, "Flat")

            manager.updateOutputPreset(named: nil, for: "headphones")
            let restored = PresetManager(storage: storage, directory: directory)
            XCTAssertNil(restored.preset(forOutputDevice: "headphones"))
        }
    }

    func testUnknownPresetDoesNotReplaceAssignment() throws {
        try withPresets { manager, _, _ in
            manager.updateOutputPreset(named: "Flat", for: "headphones")
            manager.updateOutputPreset(named: "Missing", for: "headphones")
            XCTAssertEqual(manager.preset(forOutputDevice: "headphones")?.metadata.name, "Flat")
        }
    }

    func testRenamingAndDeletingPresetUpdateAllAssignments() throws {
        try withPresets { manager, storage, directory in
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            manager.updateOutputPreset(named: "Bass Boost", for: "usb-dac")
            manager.updateOutputPreset(named: "Flat", for: "speakers")
            try manager.renamePreset(from: "Bass Boost", to: "IEMs")

            let restored = PresetManager(storage: storage, directory: directory)
            XCTAssertEqual(restored.preset(forOutputDevice: "headphones")?.metadata.name, "IEMs")
            XCTAssertEqual(restored.preset(forOutputDevice: "usb-dac")?.metadata.name, "IEMs")

            try restored.deletePreset(named: "IEMs")
            let reloaded = PresetManager(storage: storage, directory: directory)
            XCTAssertNil(reloaded.outputPresets["headphones"])
            XCTAssertNil(reloaded.outputPresets["usb-dac"])
            XCTAssertEqual(reloaded.preset(forOutputDevice: "speakers")?.metadata.name, "Flat")
        }
    }

    func testFailedRenameAndDeleteKeepAssignments() throws {
        try withPresets { manager, _, _ in
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            XCTAssertThrowsError(try manager.renamePreset(from: "Bass Boost", to: "Flat"))
            XCTAssertThrowsError(try manager.deletePreset(named: "Missing"))
            XCTAssertEqual(manager.preset(forOutputDevice: "headphones")?.metadata.name, "Bass Boost")
        }
    }

    func testOverwritingPresetKeepsAssignment() throws {
        try withPresets { manager, _, _ in
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            var preset = try XCTUnwrap(manager.preset(named: "Bass Boost"))
            preset.settings.inputGain = -12
            try manager.savePreset(preset)
            XCTAssertEqual(manager.preset(forOutputDevice: "headphones")?.settings.inputGain, -12)
        }
    }

    func testMissingPresetFileDoesNotFallBackToFlat() throws {
        try withPresets { manager, storage, directory in
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            let preset = try XCTUnwrap(manager.preset(named: "Bass Boost"))
            // Simulate a preset moved out of the library while Equaliser was closed.
            try FileManager.default.moveItem(
                at: directory.appendingPathComponent(preset.filename),
                to: directory.appendingPathComponent("moved-preset.json")
            )
            let restored = PresetManager(storage: storage, directory: directory)
            XCTAssertNil(restored.preset(forOutputDevice: "headphones"))
        }
    }

    func testOutputChangeAppliesPresetBandsAndGains() throws {
        try withPresets { manager, storage, _ in
            let store = makeStore(manager: manager, storage: storage)
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")

            // Manual selection uses the store setter.
            store.selectedOutputDeviceID = "headphones"
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
            XCTAssertEqual(store.inputGain, FactoryPresets.bassBoost.settings.inputGain)
            XCTAssertEqual(store.outputGain, FactoryPresets.bassBoost.settings.outputGain)
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, FactoryPresets.bassBoost.settings.leftBands[0].gain)
            XCTAssertFalse(manager.isModified)

            // System-default changes and disconnect fallback update the coordinator directly.
            manager.updateOutputPreset(named: "Flat", for: "speakers")
            store.routingCoordinator.selectedOutputDeviceID = "speakers"
            XCTAssertEqual(manager.selectedPresetName, "Flat")
            XCTAssertEqual(store.inputGain, 0)
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, 0)
        }
    }

    func testUnassignedOutputAndRepeatedSelectionPreserveUnsavedEdits() throws {
        try withPresets { manager, storage, _ in
            let store = makeStore(manager: manager, storage: storage)
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            store.selectedOutputDeviceID = "headphones"
            store.updateBandGain(index: 0, gain: 3)

            store.routingCoordinator.selectedOutputDeviceID = "headphones"
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, 3)
            XCTAssertTrue(manager.isModified)

            store.selectedOutputDeviceID = "speakers"
            store.selectedOutputDeviceID = nil
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, 3)
            XCTAssertTrue(manager.isModified)

            // Returning to an assigned device reapplies the saved preset, even if
            // its name is still selected with unsaved edits.
            store.selectedOutputDeviceID = "headphones"
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, FactoryPresets.bassBoost.settings.leftBands[0].gain)
            XCTAssertFalse(manager.isModified)
        }
    }

    func testManualPresetChoiceLastsUntilOutputChanges() throws {
        try withPresets { manager, storage, _ in
            let store = makeStore(manager: manager, storage: storage)
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            store.selectedOutputDeviceID = "headphones"
            store.loadPreset(named: "Flat")
            store.routingCoordinator.selectedOutputDeviceID = "headphones"
            XCTAssertEqual(manager.selectedPresetName, "Flat")

            store.selectedOutputDeviceID = "speakers"
            store.selectedOutputDeviceID = "headphones"
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
        }
    }

    func testStartupAppliesRestoredOutputAssignment() throws {
        try withPresets { manager, storage, _ in
            manager.updateOutputPreset(named: "Bass Boost", for: "headphones")
            let store = makeStore(manager: manager, storage: storage, output: "headphones")
            XCTAssertEqual(store.selectedOutputDeviceID, "headphones")
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
            XCTAssertEqual(store.inputGain, FactoryPresets.bassBoost.settings.inputGain)
            XCTAssertFalse(manager.isModified)
        }
    }

    func testDeviceNamesPersistWhileOutputsAreUnavailable() throws {
        try withPresets { manager, storage, directory in
            manager.rememberOutputDevices([
                AudioDevice(id: 1, uid: "speakers", name: "MacBook Speakers", transportType: 0),
                AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", transportType: 0),
            ])
            manager.rememberOutputDevices([
                AudioDevice(id: 3, uid: "headphones", name: "External Headphones", transportType: 0),
            ])
            let restored = PresetManager(storage: storage, directory: directory)
            XCTAssertEqual(restored.outputDeviceNames["speakers"], "MacBook Speakers")
            XCTAssertEqual(restored.outputDeviceNames["headphones"], "External Headphones")
            XCTAssertNil(restored.outputDeviceNames[DRIVER_DEVICE_UID])
        }
    }

    func testDevicePanelIncludesInactiveAndUnavailableOutputs() throws {
        try withPresets { manager, storage, _ in
            let store = makeStore(manager: manager, storage: storage, output: "headphones")
            store.deviceManager.outputDevices = [
                AudioDevice(id: 1, uid: "speakers", name: "MacBook Speakers", transportType: 0),
                AudioDevice(id: 2, uid: "headphones", name: "External Headphones", transportType: 0),
            ]
            let viewModel = DevicePresetsViewModel(store: store)
            XCTAssertTrue(try XCTUnwrap(viewModel.devices.first { $0.uid == "speakers" }).isAvailable)
            XCTAssertFalse(try XCTUnwrap(viewModel.devices.first { $0.uid == "speakers" }).isSelected)

            store.deviceManager.outputDevices = [
                AudioDevice(id: 2, uid: "headphones", name: "External Headphones", transportType: 0),
            ]
            let speakers = try XCTUnwrap(viewModel.devices.first { $0.uid == "speakers" })
            XCTAssertEqual(speakers.name, "MacBook Speakers")
            XCTAssertFalse(speakers.isAvailable)
            XCTAssertTrue(try XCTUnwrap(viewModel.devices.first { $0.uid == "headphones" }).isSelected)
        }
    }

    func testEditingInactiveOutputDoesNotChangeCurrentEQ() throws {
        try withPresets { manager, storage, _ in
            let store = makeStore(manager: manager, storage: storage, output: "headphones")
            store.loadPreset(named: "Bass Boost")
            store.updateBandGain(index: 0, gain: 3)
            let viewModel = DevicePresetsViewModel(store: store)

            viewModel.updatePreset(named: "Flat", for: "speakers")
            XCTAssertEqual(viewModel.presetName(for: "speakers"), "Flat")
            XCTAssertEqual(store.selectedOutputDeviceID, "headphones")
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, 3)
            XCTAssertTrue(manager.isModified)

            store.selectedOutputDeviceID = "speakers"
            XCTAssertEqual(manager.selectedPresetName, "Flat")
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, 0)
        }
    }

    func testEditingCurrentOutputAppliesPresetAndClearingKeepsEQ() throws {
        try withPresets { manager, storage, _ in
            let store = makeStore(manager: manager, storage: storage, output: "headphones")
            let viewModel = DevicePresetsViewModel(store: store)
            viewModel.updatePreset(named: "Bass Boost", for: "headphones")
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
            store.updateBandGain(index: 0, gain: 3)

            viewModel.updatePreset(named: nil, for: "headphones")
            XCTAssertNil(viewModel.presetName(for: "headphones"))
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
            XCTAssertEqual(store.eqConfiguration.bands[0].gain, 3)
            XCTAssertTrue(manager.isModified)
        }
    }

    func testDevicePanelDistinguishesMatchingNamesAndIncludesLegacyAssignments() throws {
        try withPresets { manager, storage, _ in
            let store = makeStore(manager: manager, storage: storage)
            store.deviceManager.outputDevices = [
                AudioDevice(id: 1, uid: "usb-dac-1", name: "USB DAC", transportType: 0),
                AudioDevice(id: 2, uid: "usb-dac-2", name: "USB DAC", transportType: 0),
            ]
            manager.updateOutputPreset(named: "Flat", for: "legacy-output")
            let viewModel = DevicePresetsViewModel(store: store)
            let dacs = viewModel.devices.filter { $0.name == "USB DAC" }
            XCTAssertEqual(dacs.map(\.uid), ["usb-dac-1", "usb-dac-2"])
            XCTAssertTrue(viewModel.devices.contains { $0.uid == "legacy-output" })

            viewModel.updatePreset(named: "Bass Boost", for: "usb-dac-1")
            viewModel.updatePreset(named: "Flat", for: "usb-dac-2")
            XCTAssertEqual(viewModel.presetName(for: "usb-dac-1"), "Bass Boost")
            XCTAssertEqual(viewModel.presetName(for: "usb-dac-2"), "Flat")
        }
    }

    func testSerialLessUSBDeviceSharesOneAssignmentAcrossPorts() throws {
        try withPresets { _, storage, directory in
            // Assignments saved per port before port-independent keys existed.
            let port1 = "AppleUSBAudioEngine:Acme:USB DAC:1100000:1"
            let port2 = "AppleUSBAudioEngine:Acme:USB DAC:1140000:1"
            let port3 = "AppleUSBAudioEngine:Acme:USB DAC:2140000:1"
            storage.set([port1: "Bass Boost", port3: "Bass Boost"], forKey: "equaliser.outputPresets")
            storage.set(
                [port1: "USB DAC", port2: "USB DAC", port3: "USB DAC", "speakers": "Speakers"],
                forKey: "equaliser.outputDeviceNames"
            )
            let manager = PresetManager(storage: storage, directory: directory)
            let store = makeStore(manager: manager, storage: storage)
            store.deviceManager.outputDevices = [
                AudioDevice(id: 1, uid: port2, name: "USB DAC", transportType: 0),
            ]

            let viewModel = DevicePresetsViewModel(store: store)
            let dacs = viewModel.devices.filter { $0.name == "USB DAC" }
            XCTAssertEqual(dacs.count, 1)
            XCTAssertTrue(try XCTUnwrap(dacs.first).isAvailable)

            // The port that never had an assignment now uses the device's preset.
            store.selectedOutputDeviceID = port2
            XCTAssertEqual(manager.selectedPresetName, "Bass Boost")
            XCTAssertTrue(try XCTUnwrap(viewModel.devices.first { $0.name == "USB DAC" }).isSelected)

            // Editing from any port updates the single shared entry.
            viewModel.updatePreset(named: "Flat", for: try XCTUnwrap(dacs.first).uid)
            XCTAssertEqual(manager.selectedPresetName, "Flat")
            XCTAssertEqual(manager.preset(forOutputDevice: port1)?.metadata.name, "Flat")
        }
    }

    private func makeStore(manager: PresetManager, storage: UserDefaults, output: String? = nil) -> EqualiserStore {
        let persistence = AppStatePersistence(storage: storage)
        var snapshot = AppStateSnapshot.default
        // With no input selected, these tests never start an audio pipeline.
        snapshot.manualModeEnabled = true
        snapshot.outputDeviceID = output
        persistence.save(snapshot)
        return EqualiserStore(persistence: persistence, presetManager: manager)
    }

    private func withPresets(_ body: (PresetManager, UserDefaults, URL) throws -> Void) throws {
        let suite = "OutputPresetTests.\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            storage.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let manager = PresetManager(storage: storage, directory: directory)
        try body(manager, storage, directory)
    }
}

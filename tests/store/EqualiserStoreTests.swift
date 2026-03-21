import XCTest
@testable import Equaliser

@MainActor
final class EqualiserStoreTests: XCTestCase {

    // MARK: - OutputDeviceSelection Tests

    func testDetermineAutomaticOutputDevice_preservesValidSelection() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in Speakers", isInput: false, isOutput: true, transportType: 0),
            AudioDevice(id: 3, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in Speakers", isInput: false, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "BlackHole 2ch", name: "BlackHole 2ch", isInput: true, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: "builtin", name: "Built-in Speakers", isInput: false, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in Speakers", isInput: false, isOutput: true, transportType: 0),
        ]

        // Valid current selection should take precedence over mac default
        let result = OutputDeviceSelection.determine(
            currentSelected: "airpods",
            macDefault: "builtin",
            availableDevices: devices
        )

        XCTAssertEqual(result, .preserveCurrent("airpods"))
    }

    func testDetermineAutomaticOutputDevice_noCurrent_noMacDefault_needsFallback() {
        let devices = [
            AudioDevice(id: 1, uid: "builtin", name: "Built-in Speakers", isInput: false, isOutput: true, transportType: 0),
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
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
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
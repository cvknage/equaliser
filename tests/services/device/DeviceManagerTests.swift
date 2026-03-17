import XCTest
@testable import Equaliser

// Transport type constants for testing (must match DeviceManager.swift)
private let kAudioDeviceTransportTypeVirtual: UInt32 = 0x76697274    // 'virt'
private let kAudioDeviceTransportTypeAggregate: UInt32 = 0x61676720  // 'agg '

final class DeviceManagerTests: XCTestCase {

    @MainActor
    func testShouldIncludeDevice_systemAggregate_excluded() {
        let manager = DeviceManager()

        XCTAssertFalse(manager.shouldIncludeDevice(name: "CADefaultDeviceAggregate"))
        XCTAssertFalse(manager.shouldIncludeDevice(name: "CADefaultDeviceAggregate-0x12345"))
    }

    @MainActor
    func testShouldIncludeDevice_userAggregate_included() {
        let manager = DeviceManager()

        let result = manager.shouldIncludeDevice(name: "My Custom Aggregate")

        XCTAssertTrue(result, "User-created aggregate devices should be included")
    }

    @MainActor
    func testShouldIncludeDevice_regularDevice_included() {
        let manager = DeviceManager()

        XCTAssertTrue(manager.shouldIncludeDevice(name: "MacBook Pro Speakers"))
        XCTAssertTrue(manager.shouldIncludeDevice(name: "Focusrite Scarlett 2i2"))
        XCTAssertTrue(manager.shouldIncludeDevice(name: "AirPods Pro"))
        XCTAssertTrue(manager.shouldIncludeDevice(name: "BlackHole 2ch"))
    }

    @MainActor
    func testShouldIncludeDevice_userAggregateWithDefaultInName_included() {
        let manager = DeviceManager()

        let result = manager.shouldIncludeDevice(name: "Default Desktop Audio")

        XCTAssertTrue(result, "User aggregate with 'Default' in name should be included")
    }

    // MARK: - AudioDevice.isVirtual Tests

    func testIsVirtual_transportTypeVirtual_returnsTrue() {
        let device = AudioDevice(
            id: 1,
            uid: "com.unknown.virtual",
            name: "Unknown Virtual Device",
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeVirtual
        )
        XCTAssertTrue(device.isVirtual, "Device with virtual transport type should be virtual")
    }

    func testIsVirtual_driverUID_fallbackWhenTransportUnknown_returnsTrue() {
        let device = AudioDevice(
            id: 2,
            uid: DRIVER_DEVICE_UID,
            name: "Equaliser",
            isInput: true,
            isOutput: true,
            transportType: 0
        )
        XCTAssertTrue(device.isVirtual, "Driver UID should be virtual via fallback")
    }

    func testIsVirtual_driverUIDPrefix_fallbackWhenTransportUnknown_returnsTrue() {
        let device = AudioDevice(
            id: 3,
            uid: "Equaliser_UID_123",
            name: "Some Device",
            isInput: true,
            isOutput: true,
            transportType: 0
        )
        XCTAssertTrue(device.isVirtual, "Driver UID prefix should be virtual via fallback")
    }

    func testIsVirtual_blackHoleUIDPrefix_fallbackWhenTransportUnknown_returnsTrue() {
        let device = AudioDevice(
            id: 4,
            uid: "BlackHole 2ch",
            name: "BlackHole 2ch",
            isInput: true,
            isOutput: true,
            transportType: 0
        )
        XCTAssertTrue(device.isVirtual, "BlackHole UID prefix should be virtual via fallback")
    }

    func testIsVirtual_physicalDevice_returnsFalse() {
        let device = AudioDevice(
            id: 5,
            uid: "com.apple.MacBookPro",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true,
            transportType: 0
        )
        XCTAssertFalse(device.isVirtual, "Physical device should not be virtual")
    }

    func testIsVirtual_externalAudioInterface_returnsFalse() {
        let device = AudioDevice(
            id: 6,
            uid: "com.focusrite.scarlett",
            name: "Focusrite Scarlett 2i2",
            isInput: true,
            isOutput: true,
            transportType: 0
        )
        XCTAssertFalse(device.isVirtual, "External audio interface should not be virtual")
    }

    func testIsVirtual_transportTypeBuiltIn_returnsFalse() {
        let device = AudioDevice(
            id: 7,
            uid: "com.apple.builtin",
            name: "Built-in Speakers",
            isInput: false,
            isOutput: true,
            transportType: 0x626C744E  // 'bltN' (built-in)
        )
        XCTAssertFalse(device.isVirtual, "Built-in device should not be virtual")
    }

    func testIsVirtual_transportTypeUSB_returnsFalse() {
        let device = AudioDevice(
            id: 8,
            uid: "com.focusrite.usb",
            name: "USB Audio Device",
            isInput: true,
            isOutput: true,
            transportType: 0x75736220  // 'usb '
        )
        XCTAssertFalse(device.isVirtual, "USB device should not be virtual")
    }

    // MARK: - AudioDevice.isAggregate Tests

    func testIsAggregate_transportTypeAggregate_returnsTrue() {
        let device = AudioDevice(
            id: 1,
            uid: "com.apple.aggregate",
            name: "Combined Output",
            isInput: false,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeAggregate
        )
        XCTAssertTrue(device.isAggregate, "Device with aggregate transport type should be aggregate")
    }

    func testIsAggregate_regularDevice_returnsFalse() {
        let device = AudioDevice(
            id: 6,
            uid: "com.focusrite.scarlett",
            name: "Focusrite Scarlett 2i2",
            isInput: true,
            isOutput: true,
            transportType: 0
        )
        XCTAssertFalse(device.isAggregate, "Regular device should not be aggregate")
    }

    func testIsAggregate_builtInSpeakers_returnsFalse() {
        let device = AudioDevice(
            id: 7,
            uid: "BuiltInSpeakerUID",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true,
            transportType: 0
        )
        XCTAssertFalse(device.isAggregate, "Built-in speakers should not be aggregate")
    }

    func testIsAggregate_nameContainsAggregate_transportTypeZero_returnsFalse() {
        // Trust system API only - name/UID heuristics removed
        let device = AudioDevice(
            id: 8,
            uid: "some-uid",
            name: "My Aggregate Device",
            isInput: false,
            isOutput: true,
            transportType: 0
        )
        XCTAssertFalse(device.isAggregate, "Device without aggregate transport type should not be aggregate, regardless of name")
    }

    // MARK: - DeviceManager.selectFallbackOutputDevice Tests

    @MainActor
    func testSelectFallbackOutputDevice_builtinSpeakersPreferred() {
        let devices = [
            AudioDevice(id: 1, uid: "external", name: "External Headphones", isInput: false, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in Speakers", isInput: false, isOutput: true, transportType: 0),
            AudioDevice(id: 3, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertEqual(fallback?.name, "Built-in Speakers")
    }

    @MainActor
    func testSelectFallbackOutputDevice_builtinInName_returnsTrue() {
        let devices = [
            AudioDevice(id: 1, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "builtin", name: "Built-in", isInput: false, isOutput: true, transportType: 0),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertEqual(fallback?.name, "Built-in")
    }

    @MainActor
    func testSelectFallbackOutputDevice_noBuiltIn_returnsFirstNonVirtual() {
        let devices = [
            AudioDevice(id: 1, uid: DRIVER_DEVICE_UID, name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "airpods", name: "AirPods Pro", isInput: true, isOutput: true, transportType: 0),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertEqual(fallback?.name, "AirPods Pro")
    }

    @MainActor
    func testSelectFallbackOutputDevice_onlyVirtual_returnsNil() {
        let devices = [
            AudioDevice(id: 1, uid: "Equaliser_UID", name: "Equaliser", isInput: true, isOutput: true, transportType: 0),
            AudioDevice(id: 2, uid: "BlackHole 2ch", name: "BlackHole 2ch", isInput: true, isOutput: true, transportType: 0),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertNil(fallback)
    }

    @MainActor
    func testSelectFallbackOutputDevice_excludesAggregate_byTransportType() {
        let devices = [
            AudioDevice(id: 1, uid: "agg", name: "My Aggregate Device", isInput: false, isOutput: true, transportType: kAudioDeviceTransportTypeAggregate),
            AudioDevice(id: 2, uid: "speaker", name: "External Speaker", isInput: false, isOutput: true, transportType: 0),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertEqual(fallback?.name, "External Speaker")
    }

    @MainActor
    func testSelectFallbackOutputDevice_emptyArray_returnsNil() {
        let devices: [AudioDevice] = []

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertNil(fallback)
    }

    @MainActor
    func testSelectFallbackOutputDevice_allAggregate_byTransportType_returnsNil() {
        let devices = [
            AudioDevice(id: 1, uid: "agg1", name: "Aggregate 1", isInput: false, isOutput: true, transportType: kAudioDeviceTransportTypeAggregate),
            AudioDevice(id: 2, uid: "agg2", name: "Multi-Output Device", isInput: false, isOutput: true, transportType: kAudioDeviceTransportTypeAggregate),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertNil(fallback)
    }

    @MainActor
    func testSelectFallbackOutputDevice_excludesVirtualByTransportType() {
        let devices = [
            AudioDevice(id: 1, uid: "virtual1", name: "Virtual Device", isInput: true, isOutput: true, transportType: kAudioDeviceTransportTypeVirtual),
            AudioDevice(id: 2, uid: "physical", name: "Real Speakers", isInput: false, isOutput: true, transportType: 0x626C744E),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertEqual(fallback?.name, "Real Speakers", "Should exclude virtual devices by transport type")
    }

    @MainActor
    func testSelectFallbackOutputDevice_excludesAggregateByTransportType() {
        let devices = [
            AudioDevice(id: 1, uid: "agg1", name: "Combined Output", isInput: false, isOutput: true, transportType: kAudioDeviceTransportTypeAggregate),
            AudioDevice(id: 2, uid: "speaker", name: "External Speaker", isInput: false, isOutput: true, transportType: 0),
        ]

        let fallback = DeviceManager.selectFallbackOutputDevice(from: devices)
        XCTAssertEqual(fallback?.name, "External Speaker", "Should exclude aggregate devices by transport type")
    }
}
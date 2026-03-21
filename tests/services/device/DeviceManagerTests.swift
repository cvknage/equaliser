import XCTest
@testable import Equaliser

// Transport type constants for testing (must match CoreAudio FourCharCodes)
private let kAudioDeviceTransportTypeVirtual: UInt32 = 0x76697274    // 'virt'
private let kAudioDeviceTransportTypeAggregate: UInt32 = 0x61676720  // 'agg '
private let kAudioDeviceTransportTypeBuiltIn: UInt32 = 0x626C746E    // 'bltn'

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
            transportType: kAudioDeviceTransportTypeBuiltIn
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

    // MARK: - AudioDevice.isRealDevice Tests

    func testIsRealDevice_excludesDriver() {
        let device = AudioDevice(
            id: 1,
            uid: "Equaliser_UID_123",
            name: "Equaliser",
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeVirtual
        )
        XCTAssertFalse(device.isRealDevice, "Driver should be excluded")
    }
    
    func testIsRealDevice_excludesVirtual() {
        let device = AudioDevice(
            id: 1,
            uid: "BlackHole_2ch",
            name: "BlackHole 2ch",
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeVirtual
        )
        XCTAssertFalse(device.isRealDevice, "Virtual devices should be excluded")
    }
    
    func testIsRealDevice_excludesAggregate() {
        let device = AudioDevice(
            id: 1,
            uid: "agg1",
            name: "My Aggregate",
            isInput: false,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeAggregate
        )
        XCTAssertFalse(device.isRealDevice, "Aggregates should be excluded")
    }
    
    func testIsRealDevice_acceptsPhysicalDevice() {
        let device = AudioDevice(
            id: 1,
            uid: "builtin-speakers",
            name: "Built-in Speakers",
            isInput: false,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeBuiltIn
        )
        XCTAssertTrue(device.isRealDevice, "Physical devices should be accepted")
    }
    
    func testIsRealDevice_acceptsUSBDevice() {
        let usbTransportType: UInt32 = 0x75736220  // 'usb '
        let device = AudioDevice(
            id: 1,
            uid: "usb-headphones",
            name: "USB Headphones",
            isInput: true,
            isOutput: true,
            transportType: usbTransportType
        )
        XCTAssertTrue(device.isRealDevice, "USB devices should be accepted")
    }
    
    func testIsRealDevice_acceptsBTDevice() {
        let btTransportType: UInt32 = 0x626C7461  // 'blta'
        let device = AudioDevice(
            id: 1,
            uid: "bt-headphones",
            name: "Bluetooth Headphones",
            isInput: true,
            isOutput: true,
            transportType: btTransportType
        )
        XCTAssertTrue(device.isRealDevice, "Bluetooth devices should be accepted")
    }
    
    func testIsRealDevice_excludesDriverEvenWithPhysicalTransport() {
        // Driver UID prefix should exclude even if transport type looks physical
        let device = AudioDevice(
            id: 1,
            uid: "Equaliser_driver",
            name: "Equaliser",
            isInput: true,
            isOutput: true,
            transportType: 0  // Unknown transport, but UID prefix should exclude
        )
        XCTAssertFalse(device.isRealDevice, "Driver should be excluded by UID prefix")
    }

    // MARK: - AudioDevice.isValidForSelection Tests
    
    func testIsValidForSelection_excludesOnlyDriver() {
        // Driver should be excluded
        let driverDevice = AudioDevice(
            id: 1,
            uid: "Equaliser_UID",
            name: "Equaliser",
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeVirtual
        )
        XCTAssertFalse(driverDevice.isValidForSelection, "Driver should be excluded from selection")
        
        // Virtual devices (BlackHole) should be accepted for selection
        let blackholeDevice = AudioDevice(
            id: 2,
            uid: "BlackHole_2ch",
            name: "BlackHole",
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeVirtual
        )
        XCTAssertTrue(blackholeDevice.isValidForSelection, "Virtual devices should be accepted for selection")
        
        // Aggregates should be accepted for selection
        let aggregateDevice = AudioDevice(
            id: 3,
            uid: "my-aggregate",
            name: "My Aggregate",
            isInput: false,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeAggregate
        )
        XCTAssertTrue(aggregateDevice.isValidForSelection, "Aggregates should be accepted for selection")
        
        // Physical devices should be accepted
        let physicalDevice = AudioDevice(
            id: 4,
            uid: "headphones",
            name: "Headphones",
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeBuiltIn
        )
        XCTAssertTrue(physicalDevice.isValidForSelection, "Physical devices should be accepted for selection")
    }
}
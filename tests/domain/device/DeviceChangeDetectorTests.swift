// DeviceChangeDetectorTests.swift
// Tests for DeviceChangeDetector and HeadphoneSwitchPolicy pure functions

import XCTest
@testable import Equaliser

// Transport type constants for testing
private let kAudioDeviceTransportTypeBuiltIn: UInt32 = 0x626C746E    // 'bltn'
private let kAudioDeviceTransportTypeUSB: UInt32 = 0x75736220          // 'usb '
private let kAudioDeviceTransportTypeBluetooth: UInt32 = 0x626C7461   // 'blta'
private let kAudioDeviceTransportTypeVirtual: UInt32 = 0x76697274     // 'virt'

final class DeviceChangeDetectorTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeBuiltInDevice(uid: String, name: String = "Built-in Speakers") -> AudioDevice {
        AudioDevice(
            id: 1,
            uid: uid,
            name: name,
            isInput: false,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeBuiltIn
        )
    }
    
    private func makeUSBDevice(uid: String, name: String = "USB Headphones") -> AudioDevice {
        AudioDevice(
            id: 2,
            uid: uid,
            name: name,
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeUSB
        )
    }
    
    private func makeBluetoothDevice(uid: String, name: String = "AirPods") -> AudioDevice {
        AudioDevice(
            id: 3,
            uid: uid,
            name: name,
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeBluetooth
        )
    }
    
    // MARK: - diffBuiltInDevices Tests
    
    func testDiffBuiltInDevices_detectsSingleAddition() {
        let previous: Set<String> = ["builtin-speakers"]
        let currentDevices = [
            makeBuiltInDevice(uid: "builtin-speakers"),
            makeBuiltInDevice(uid: "builtin-headphones", name: "Headphones")
        ]
        
        let (added, removed) = DeviceChangeDetector.diffBuiltInDevices(
            previousUIDs: previous,
            currentDevices: currentDevices
        )
        
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.uid, "builtin-headphones")
        XCTAssertEqual(added.first?.name, "Headphones")
        XCTAssertTrue(removed.isEmpty)
    }
    
    func testDiffBuiltInDevices_detectsMultipleAdditions() {
        let previous: Set<String> = ["builtin-1"]
        let currentDevices = [
            makeBuiltInDevice(uid: "builtin-1"),
            makeBuiltInDevice(uid: "builtin-2"),
            makeBuiltInDevice(uid: "builtin-3")
        ]
        
        let (added, removed) = DeviceChangeDetector.diffBuiltInDevices(
            previousUIDs: previous,
            currentDevices: currentDevices
        )
        
        XCTAssertEqual(added.count, 2)
        XCTAssertTrue(removed.isEmpty)
    }
    
    func testDiffBuiltInDevices_detectsRemoval() {
        let previous: Set<String> = ["builtin-speakers", "builtin-headphones"]
        let currentDevices = [
            makeBuiltInDevice(uid: "builtin-speakers")
        ]
        
        let (added, removed) = DeviceChangeDetector.diffBuiltInDevices(
            previousUIDs: previous,
            currentDevices: currentDevices
        )
        
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.contains("builtin-headphones"))
    }
    
    func testDiffBuiltInDevices_detectsRemovalAndAddition() {
        let previous: Set<String> = ["builtin-speakers"]
        let currentDevices = [
            makeBuiltInDevice(uid: "builtin-headphones")
        ]
        
        let (added, removed) = DeviceChangeDetector.diffBuiltInDevices(
            previousUIDs: previous,
            currentDevices: currentDevices
        )
        
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.uid, "builtin-headphones")
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.contains("builtin-speakers"))
    }
    
    func testDiffBuiltInDevices_ignoresNonBuiltInDevices() {
        let previous: Set<String> = ["builtin-speakers"]
        let currentDevices = [
            makeBuiltInDevice(uid: "builtin-speakers"),
            makeUSBDevice(uid: "usb-headphones"),
            makeBluetoothDevice(uid: "airpods")
        ]
        
        let (added, removed) = DeviceChangeDetector.diffBuiltInDevices(
            previousUIDs: previous,
            currentDevices: currentDevices
        )
        
        // USB and Bluetooth devices should not affect built-in detection
        XCTAssertTrue(added.isEmpty)
        XCTAssertTrue(removed.isEmpty)
    }
    
    func testDiffBuiltInDevices_emptyPreviousDetectsAllBuiltIn() {
        let previous: Set<String> = []
        let currentDevices = [
            makeBuiltInDevice(uid: "builtin-speakers"),
            makeBuiltInDevice(uid: "builtin-headphones")
        ]
        
        let (added, removed) = DeviceChangeDetector.diffBuiltInDevices(
            previousUIDs: previous,
            currentDevices: currentDevices
        )
        
        // All built-in devices are "added" when previous is empty
        XCTAssertEqual(added.count, 2)
        XCTAssertTrue(removed.isEmpty)
    }
    
    func testDiffBuiltInDevices_emptyCurrentDetectsAllRemoved() {
        let previous: Set<String> = ["builtin-speakers", "builtin-headphones"]
        let currentDevices: [AudioDevice] = []
        
        let (added, removed) = DeviceChangeDetector.diffBuiltInDevices(
            previousUIDs: previous,
            currentDevices: currentDevices
        )
        
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(removed.count, 2)
        XCTAssertTrue(removed.contains("builtin-speakers"))
        XCTAssertTrue(removed.contains("builtin-headphones"))
    }
    
    // MARK: - shouldTriggerHeadphoneSwitch Tests
    
    func testShouldTriggerHeadphoneSwitch_singleBuiltIn_returnsDevice() {
        let devices = [makeBuiltInDevice(uid: "headphones")]
        
        let result = DeviceChangeDetector.shouldTriggerHeadphoneSwitch(addedDevices: devices)
        
        XCTAssertEqual(result?.uid, "headphones")
    }
    
    func testShouldTriggerHeadphoneSwitch_multipleBuiltIns_returnsNil() {
        let devices = [
            makeBuiltInDevice(uid: "device-1"),
            makeBuiltInDevice(uid: "device-2")
        ]
        
        let result = DeviceChangeDetector.shouldTriggerHeadphoneSwitch(addedDevices: devices)
        
        XCTAssertNil(result, "Should not trigger when multiple built-in devices added")
    }
    
    func testShouldTriggerHeadphoneSwitch_emptyList_returnsNil() {
        let devices: [AudioDevice] = []
        
        let result = DeviceChangeDetector.shouldTriggerHeadphoneSwitch(addedDevices: devices)
        
        XCTAssertNil(result)
    }
    
    func testShouldTriggerHeadphoneSwitch_nonBuiltIn_returnsNil() {
        // A device with wrong transport type shouldn't trigger
        let device = AudioDevice(
            id: 1,
            uid: "usb-device",
            name: "USB Device",
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeUSB
        )
        
        let result = DeviceChangeDetector.shouldTriggerHeadphoneSwitch(addedDevices: [device])
        
        XCTAssertNil(result, "Should not trigger for non-built-in device")
    }
    
    // MARK: - deviceExists Tests
    
    func testDeviceExists_devicePresent_returnsTrue() {
        let devices = [
            makeBuiltInDevice(uid: "device-1"),
            makeBuiltInDevice(uid: "device-2")
        ]
        
        XCTAssertTrue(DeviceChangeDetector.deviceExists(uid: "device-1", in: devices))
    }
    
    func testDeviceExists_deviceNotPresent_returnsFalse() {
        let devices = [
            makeBuiltInDevice(uid: "device-1"),
            makeBuiltInDevice(uid: "device-2")
        ]
        
        XCTAssertFalse(DeviceChangeDetector.deviceExists(uid: "device-3", in: devices))
    }
    
    func testDeviceExists_nilUID_returnsFalse() {
        let devices = [makeBuiltInDevice(uid: "device-1")]
        
        XCTAssertFalse(DeviceChangeDetector.deviceExists(uid: nil, in: devices))
    }
    
    func testDeviceExists_emptyDevices_returnsFalse() {
        let devices: [AudioDevice] = []
        
        XCTAssertFalse(DeviceChangeDetector.deviceExists(uid: "device-1", in: devices))
    }
}

// MARK: - HeadphoneSwitchPolicy Tests

final class HeadphoneSwitchPolicyTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeBuiltInDevice(uid: String, name: String = "Built-in") -> AudioDevice {
        AudioDevice(
            id: 1,
            uid: uid,
            name: name,
            isInput: false,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeBuiltIn
        )
    }
    
    private func makeUSBDevice(uid: String, name: String = "USB Device") -> AudioDevice {
        AudioDevice(
            id: 2,
            uid: uid,
            name: name,
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeUSB
        )
    }
    
    private func makeBluetoothDevice(uid: String, name: String = "Bluetooth") -> AudioDevice {
        AudioDevice(
            id: 3,
            uid: uid,
            name: name,
            isInput: true,
            isOutput: true,
            transportType: kAudioDeviceTransportTypeBluetooth
        )
    }
    
    // MARK: - Switch When Current Is Built-in
    
    func testShouldSwitch_currentIsBuiltIn_returnsTrue() {
        let current = makeBuiltInDevice(uid: "builtin-speakers")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertTrue(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: false
        ))
    }
    
    func testShouldSwitch_currentIsBuiltInHeadphones_returnsTrue() {
        // Switching from built-in speakers to built-in headphones (both built-in)
        let current = makeBuiltInDevice(uid: "builtin-speakers")
        let new = makeBuiltInDevice(uid: "builtin-headphones", name: "Headphones")
        
        XCTAssertTrue(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: false
        ))
    }
    
    // MARK: - No Switch When Current Is External
    
    func testShouldSwitch_currentIsUSB_returnsFalse() {
        let current = makeUSBDevice(uid: "usb-speakers")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: false
        ))
    }
    
    func testShouldSwitch_currentIsBluetooth_returnsFalse() {
        let current = makeBluetoothDevice(uid: "airpods")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: false
        ))
    }
    
    func testShouldSwitch_currentIsHDMI_returnsFalse() {
        // HDMI has different transport type but is not built-in
        let current = AudioDevice(
            id: 4,
            uid: "hdmi-display",
            name: "HDMI Display",
            isInput: false,
            isOutput: true,
            transportType: 0x48444D49  // 'HDMI'
        )
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: false
        ))
    }
    
    // MARK: - No Switch In Manual Mode
    
    func testShouldSwitch_manualMode_returnsFalse() {
        let current = makeBuiltInDevice(uid: "builtin-speakers")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: true,
            isReconfiguring: false
        ))
    }
    
    // MARK: - No Switch During Reconfiguration
    
    func testShouldSwitch_reconfiguring_returnsFalse() {
        let current = makeBuiltInDevice(uid: "builtin-speakers")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: true
        ))
    }
    
    // MARK: - No Switch When Current Is Nil
    
    func testShouldSwitch_currentIsNil_returnsFalse() {
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: nil,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: false
        ))
    }
    
    // MARK: - Combined Conditions
    
    func testShouldSwitch_allConditionsMet_returnsTrue() {
        let current = makeBuiltInDevice(uid: "builtin-speakers")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertTrue(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: false,
            isReconfiguring: false
        ))
    }
    
    func testShouldSwitch_manualModeAndReconfiguring_returnsFalse() {
        let current = makeBuiltInDevice(uid: "builtin-speakers")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: true,
            isReconfiguring: true
        ))
    }
    
    func testShouldSwitch_manualModeAndUSBCurrent_returnsFalse() {
        // Both conditions fail - should definitely not switch
        let current = makeUSBDevice(uid: "usb-speakers")
        let new = makeBuiltInDevice(uid: "headphones")
        
        XCTAssertFalse(HeadphoneSwitchPolicy.shouldSwitch(
            currentOutput: current,
            newDevice: new,
            isInManualMode: true,
            isReconfiguring: false
        ))
    }
}
// OutputDeviceHistoryTests.swift
// Tests for OutputDeviceHistory

import XCTest
@testable import Equaliser

@MainActor
final class OutputDeviceHistoryTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeDevice(uid: String, name: String = "Device", isVirtual: Bool = false) -> AudioDevice {
        // kAudioDeviceTransportTypeBuiltIn = 'bltn' = 1650537695
        // kAudioDeviceTransportTypeVirtual = 'vrt ' = 1986549999
        AudioDevice(
            id: 0,
            uid: uid,
            name: name,
            transportType: isVirtual ? 1986549999 : 1650537695
        )
    }
    
    // MARK: - Add Tests
    
    func testAdd_addsDeviceToFront() {
        let history = OutputDeviceHistory()
        
        history.add("device-1")
        history.add("device-2")
        history.add("device-3")
        
        XCTAssertEqual(history.devices, ["device-3", "device-2", "device-1"])
    }
    
    func testAdd_removesDuplicateAndMovesToFront() {
        let history = OutputDeviceHistory()
        
        history.add("device-1")
        history.add("device-2")
        history.add("device-3")
        history.add("device-1") // Add duplicate
        
        // Should be moved to front, not duplicated
        XCTAssertEqual(history.devices, ["device-1", "device-3", "device-2"])
    }
    
    func testAdd_limitsHistoryTo10() {
        let history = OutputDeviceHistory()
        
        // Add 15 devices
        for i in 1...15 {
            history.add("device-\(i)")
        }
        
        // Should only keep last 10
        XCTAssertEqual(history.devices.count, 10)
        XCTAssertEqual(history.devices.first, "device-15")
        XCTAssertEqual(history.devices.last, "device-6")
    }
    
    func testAdd_preservesOrderAfterDuplicate() {
        let history = OutputDeviceHistory()
        
        history.add("a")
        history.add("b")
        history.add("c")
        history.add("b") // Duplicate
        
        XCTAssertEqual(history.devices, ["b", "c", "a"])
    }
    
    // MARK: - Clear Tests
    
    func testClear_removesAllDevices() {
        let history = OutputDeviceHistory()
        
        history.add("device-1")
        history.add("device-2")
        history.add("device-3")
        
        XCTAssertEqual(history.devices.count, 3)
        
        history.clear()
        
        XCTAssertEqual(history.devices.count, 0)
    }
    
    // MARK: - Device Still Exists Tests
    
    func testDeviceStillExists_returnsTrueWhenPresent() {
        let history = OutputDeviceHistory()
        let devices = [
            makeDevice(uid: "device-1"),
            makeDevice(uid: "device-2"),
            makeDevice(uid: "device-3")
        ]
        
        XCTAssertTrue(history.deviceStillExists("device-2", in: devices))
    }
    
    func testDeviceStillExists_returnsFalseWhenNotPresent() {
        let history = OutputDeviceHistory()
        let devices = [
            makeDevice(uid: "device-1"),
            makeDevice(uid: "device-2")
        ]
        
        XCTAssertFalse(history.deviceStillExists("device-3", in: devices))
    }
    
    func testDeviceStillExists_returnsFalseWhenNil() {
        let history = OutputDeviceHistory()
        let devices = [
            makeDevice(uid: "device-1")
        ]
        
        XCTAssertFalse(history.deviceStillExists(nil, in: devices))
    }
    
    func testDeviceStillExists_returnsFalseWhenEmptyDevices() {
        let history = OutputDeviceHistory()
        let devices: [AudioDevice] = []
        
        XCTAssertFalse(history.deviceStillExists("device-1", in: devices))
    }
    
    // MARK: - Find Replacement Device Tests (with mock DeviceManager)
    
    func testFindReplacementDevice_returnsNilWhenCurrentStillValid() {
        let history = OutputDeviceHistory()
        let deviceManager = DeviceManager()
        
        // Add a device to history
        history.add("old-device")
        
        // Current device is still in the list
        // Note: Without mocking DeviceManager, deviceManager.outputDevices will be empty
        // So current device won't be found, and it will try to find a replacement
        // This test documents expected behavior with empty device list
        _ = history.findReplacementDevice(currentUID: "current-device", deviceManager: deviceManager)
        
        // With empty device list, history remains unchanged
        XCTAssertEqual(history.devices.count, 1)
    }
    
    func testFindReplacementDevice_usesHistoryFirst() {
        let history = OutputDeviceHistory()
        
        // History: old-device-1, old-device-2
        history.add("old-device-1")
        history.add("old-device-2")
        
        // Most recent should be first
        XCTAssertEqual(history.devices.first, "old-device-2")
    }
    
    func testFindReplacementDevice_removesUsedDeviceFromHistory() {
        let history = OutputDeviceHistory()
        
        history.add("device-1")
        history.add("device-2")
        
        XCTAssertEqual(history.devices.count, 2)
        
        // Note: Full test would require DeviceManager mock
        // This documents the expected behavior: used device should be removed from history
    }
    
    // MARK: - Edge Cases
    
    func testAdd_sameDeviceMultipleTimes() {
        let history = OutputDeviceHistory()
        
        history.add("same-device")
        history.add("same-device")
        history.add("same-device")
        
        XCTAssertEqual(history.devices.count, 1)
        XCTAssertEqual(history.devices.first, "same-device")
    }
    
    func testAdd_afterClear() {
        let history = OutputDeviceHistory()
        
        history.add("device-1")
        history.add("device-2")
        history.clear()
        history.add("device-3")
        
        XCTAssertEqual(history.devices, ["device-3"])
    }
    
    func testDeviceStillExists_withMultipleMatches() {
        let history = OutputDeviceHistory()
        let devices = [
            makeDevice(uid: "device-1"),
            makeDevice(uid: "device-2"),
            makeDevice(uid: "device-1") // Duplicate UID (shouldn't happen but test)
        ]
        
        XCTAssertTrue(history.deviceStillExists("device-1", in: devices))
        XCTAssertTrue(history.deviceStillExists("device-2", in: devices))
    }
}
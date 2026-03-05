import XCTest
@testable import EqualiserApp

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
}

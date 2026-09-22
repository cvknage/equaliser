import XCTest

@testable import Equaliser

final class DevicePresetMapTests: XCTestCase {

    func testEmptyMapHasNoMappings() {
        let map = DevicePresetMap()
        XCTAssertNil(map.presetFor(device: "any"))
    }

    func testRecordThenLookup() {
        var map = DevicePresetMap()
        map.record(device: "macbook-speakers", presetName: "Speakers")
        map.record(device: "airpods", presetName: "Headphones")
        XCTAssertEqual(map.presetFor(device: "macbook-speakers"), "Speakers")
        XCTAssertEqual(map.presetFor(device: "airpods"), "Headphones")
    }

    func testRecordOverwrites() {
        var map = DevicePresetMap()
        map.record(device: "airpods", presetName: "Headphones")
        map.record(device: "airpods", presetName: "Flat")
        XCTAssertEqual(map.presetFor(device: "airpods"), "Flat")
    }

    func testRemove() {
        var map = DevicePresetMap()
        map.record(device: "airpods", presetName: "Headphones")
        map.remove(device: "airpods")
        XCTAssertNil(map.presetFor(device: "airpods"))
    }

    func testPruneDropsStalePresets() {
        var map = DevicePresetMap()
        map.record(device: "speakers", presetName: "Speakers")
        map.record(device: "airpods", presetName: "Deleted Preset")
        map.prune(invalidFor: ["Speakers"])
        XCTAssertEqual(map.presetFor(device: "speakers"), "Speakers")
        XCTAssertNil(map.presetFor(device: "airpods"))
    }

    func testCodableRoundTrip() throws {
        var map = DevicePresetMap()
        map.record(device: "airpods", presetName: "Headphones")

        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(DevicePresetMap.self, from: data)

        XCTAssertEqual(decoded.presetFor(device: "airpods"), "Headphones")
    }
}
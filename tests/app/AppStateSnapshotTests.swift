import XCTest
@testable import Equaliser

final class AppStateSnapshotTests: XCTestCase {
    func testStartupOutputPreference_defaultsToSavedOutput() {
        XCTAssertFalse(AppStateSnapshot.default.preferMacDefaultOnStartup)
    }

    func testStartupOutputPreference_legacySnapshotPreservesSavedOutput() throws {
        let data = Data("""
        {
            "globalBypass": false,
            "inputGain": 0,
            "outputGain": 0,
            "outputDeviceID": "speakers"
        }
        """.utf8)

        let snapshot = try JSONDecoder().decode(AppStateSnapshot.self, from: data)

        XCTAssertFalse(snapshot.preferMacDefaultOnStartup)
        XCTAssertEqual(snapshot.outputDeviceID, "speakers")
    }

    func testStartupOutputPreference_roundTripsBothChoices() throws {
        for preference in [false, true] {
            var snapshot = AppStateSnapshot.default
            snapshot.preferMacDefaultOnStartup = preference
            snapshot.outputDeviceID = "speakers"

            let data = try JSONEncoder().encode(snapshot)
            let restored = try JSONDecoder().decode(AppStateSnapshot.self, from: data)

            XCTAssertEqual(restored.preferMacDefaultOnStartup, preference)
            XCTAssertEqual(restored.outputDeviceID, "speakers")
        }
    }
}

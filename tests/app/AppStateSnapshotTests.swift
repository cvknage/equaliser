import XCTest

@testable import Equaliser

final class AppStateSnapshotTests: XCTestCase {

    func testDefaultEnablesAutoApplyDevicePresets() {
        XCTAssertTrue(AppStateSnapshot.default.autoApplyDevicePresets)
    }

    func testCodableRoundTripPreservesAutoApplyDevicePresets() throws {
        var snapshot = AppStateSnapshot.default
        snapshot.autoApplyDevicePresets = false

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppStateSnapshot.self, from: data)

        XCTAssertFalse(decoded.autoApplyDevicePresets)
    }

    func testDecodingSnapshotWithoutKeyDefaultsToEnabled() throws {
        // Simulates an app state file saved before the field existed.
        let encoded = try JSONEncoder().encode(AppStateSnapshot.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "autoApplyDevicePresets")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppStateSnapshot.self, from: legacyData)

        XCTAssertTrue(decoded.autoApplyDevicePresets)
    }
}
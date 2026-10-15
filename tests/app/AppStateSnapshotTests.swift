import XCTest
@testable import Equaliser

final class AppStateSnapshotTests: XCTestCase {
    func testSnapshotWithoutDriverNameFormatLoadsDefault() throws {
        // Snapshots saved before the format existed have no driverNameFormat key.
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppStateSnapshot.default)) as? [String: Any]
        )
        json.removeValue(forKey: "driverNameFormat")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let snapshot = try JSONDecoder().decode(AppStateSnapshot.self, from: legacy)
        XCTAssertEqual(snapshot.driverNameFormat, DriverNameFormat.default.string)
    }

    func testDriverNameFormatRoundTrips() throws {
        var snapshot = AppStateSnapshot.default
        snapshot.driverNameFormat = "Equaliser → {device} ({eq-state})"
        let decoded = try JSONDecoder().decode(AppStateSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.driverNameFormat, "Equaliser → {device} ({eq-state})")
    }
}

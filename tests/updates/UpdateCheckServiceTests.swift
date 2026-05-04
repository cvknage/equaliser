//  UpdateCheckServiceTests.swift
//  EqualiserTests
//
//  Tests for UpdateCheckService pure functions.

import XCTest
@testable import Equaliser

final class UpdateCheckServiceTests: XCTestCase {

    // MARK: - isVersion(_:newerThan:)

    func testIsVersion_NewerPatch() {
        XCTAssertTrue(UpdateCheckService.isVersion("1.3.3", newerThan: "1.3.2"))
    }

    func testIsVersion_NewerMinor() {
        XCTAssertTrue(UpdateCheckService.isVersion("1.4.0", newerThan: "1.3.2"))
    }

    func testIsVersion_NewerMajor() {
        XCTAssertTrue(UpdateCheckService.isVersion("2.0.0", newerThan: "1.9.9"))
    }

    func testIsVersion_SameVersion() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3.2", newerThan: "1.3.2"))
    }

    func testIsVersion_OlderPatch() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3.1", newerThan: "1.3.2"))
    }

    func testIsVersion_OlderMinor() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.2.9", newerThan: "1.3.2"))
    }

    func testIsVersion_NewerWithFewerComponents() {
        XCTAssertTrue(UpdateCheckService.isVersion("1.4", newerThan: "1.3.2"))
    }

    func testIsVersion_OlderWithFewerComponents() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3", newerThan: "1.3.2"))
    }

    func testIsVersion_EqualWithFewerComponents() {
        XCTAssertFalse(UpdateCheckService.isVersion("1.3", newerThan: "1.3.0"))
    }

    // MARK: - parseReleaseResponse

    func testParseReleaseResponse_ValidTagWithVPrefix() {
        let json = """
        {"tag_name": "v1.4.0", "name": "Release 1.4.0"}
        """.data(using: .utf8)!

        let result = UpdateCheckService.parseReleaseResponse(json)

        // We can't assert the exact result without knowing the current app version,
        // but we can verify it's not a parsing error.
        if case .error = result {
            XCTFail("Should not produce a parsing error for valid JSON with tag_name")
        }
    }

    func testParseReleaseResponse_MissingTagName() {
        let json = """
        {"name": "Release 1.4.0"}
        """.data(using: .utf8)!

        let result = UpdateCheckService.parseReleaseResponse(json)

        if case .error(.parsingFailed) = result {
            // Expected
        } else {
            XCTFail("Expected parsingFailed for missing tag_name, got \(result)")
        }
    }

    func testParseReleaseResponse_InvalidJSON() {
        let data = "not json at all".data(using: .utf8)!

        let result = UpdateCheckService.parseReleaseResponse(data)

        if case .error(.parsingFailed) = result {
            // Expected
        } else {
            XCTFail("Expected parsingFailed for invalid JSON, got \(result)")
        }
    }

    func testParseReleaseResponse_EmptyTagName() {
        let json = """
        {"tag_name": ""}
        """.data(using: .utf8)!

        let result = UpdateCheckService.parseReleaseResponse(json)

        if case .error(.parsingFailed) = result {
            // Expected — empty version string
        } else {
            XCTFail("Expected parsingFailed for empty tag_name, got \(result)")
        }
    }
}

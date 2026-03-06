import XCTest
@testable import EqualiserApp

@MainActor
final class MeterStoreTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInit_defaultValues_allMetersSilent() {
        let store = MeterStore()

        XCTAssertEqual(store.inputMeterLevel, .silent)
        XCTAssertEqual(store.outputMeterLevel, .silent)
        XCTAssertEqual(store.inputMeterRMS, .silent)
        XCTAssertEqual(store.outputMeterRMS, .silent)
    }

    func testInit_defaultValues_metersEnabledTrue() {
        let store = MeterStore()

        XCTAssertTrue(store.metersEnabled)
    }

    func testInit_restoresPersistedEnabledState() {
        guard let testDefaults = UserDefaults(suiteName: #function) else {
            XCTFail("Failed to create test UserDefaults")
            return
        }
        testDefaults.set(false, forKey: "equalizer.metersEnabled")

        let store = MeterStore(storage: testDefaults)

        XCTAssertFalse(store.metersEnabled)
    }

    // MARK: - metersEnabled Toggle Tests

    func testMetersEnabled_whenDisabled_setsAllMetersToSilent() {
        let store = MeterStore()

        let testState = StereoMeterState(
            left: ChannelMeterState(peak: 0.5, peakHold: 0.5, peakHoldTimeRemaining: 1.0, clipHold: 0, rms: 0.3),
            right: ChannelMeterState(peak: 0.6, peakHold: 0.6, peakHoldTimeRemaining: 1.0, clipHold: 0, rms: 0.4)
        )
        store.inputMeterLevel = testState
        store.outputMeterLevel = testState
        store.inputMeterRMS = testState
        store.outputMeterRMS = testState

        store.metersEnabled = false

        XCTAssertEqual(store.inputMeterLevel, .silent)
        XCTAssertEqual(store.outputMeterLevel, .silent)
        XCTAssertEqual(store.inputMeterRMS, .silent)
        XCTAssertEqual(store.outputMeterRMS, .silent)
    }

    func testMetersEnabled_whenEnabled_doesNotResetMeters() {
        let store = MeterStore()

        let testState = StereoMeterState(
            left: ChannelMeterState(peak: 0.5, peakHold: 0.5, peakHoldTimeRemaining: 1.0, clipHold: 0, rms: 0.3),
            right: .silent
        )
        store.inputMeterLevel = testState

        store.metersEnabled = true

        XCTAssertEqual(store.inputMeterLevel, testState)
    }

    func testMetersEnabled_persistsToStorage() {
        guard let testDefaults = UserDefaults(suiteName: #function) else {
            XCTFail("Failed to create test UserDefaults")
            return
        }
        let store = MeterStore(storage: testDefaults)

        store.metersEnabled = false
        XCTAssertFalse(testDefaults.bool(forKey: "equalizer.metersEnabled"))

        store.metersEnabled = true
        XCTAssertTrue(testDefaults.bool(forKey: "equalizer.metersEnabled"))
    }

    // MARK: - Timer Lifecycle Tests

    func testStopMeterUpdates_resetsAllMetersToSilent() {
        let store = MeterStore()

        let testState = StereoMeterState(
            left: ChannelMeterState(peak: 0.5, peakHold: 0.5, peakHoldTimeRemaining: 1.0, clipHold: 0, rms: 0.3),
            right: .silent
        )
        store.inputMeterLevel = testState
        store.outputMeterLevel = testState
        store.inputMeterRMS = testState
        store.outputMeterRMS = testState

        store.stopMeterUpdates()

        XCTAssertEqual(store.inputMeterLevel, .silent)
        XCTAssertEqual(store.outputMeterLevel, .silent)
        XCTAssertEqual(store.inputMeterRMS, .silent)
        XCTAssertEqual(store.outputMeterRMS, .silent)
    }

    func testStartMeterUpdates_withoutPipeline_noCrash() {
        let store = MeterStore()

        store.startMeterUpdates()

        XCTAssertTrue(true)
    }
}

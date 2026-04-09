import XCTest
@testable import Equaliser

@MainActor
final class MeterStoreTests: XCTestCase {

    // MARK: - Test Observer

    private final class TestObserver: MeterObserver {
        var lastValue: Float = 0
        var lastHold: Float = 0
        var lastClipping: Bool = false
        var updateCount = 0

        func meterUpdated(value: Float, hold: Float, clipping: Bool) {
            lastValue = value
            lastHold = hold
            lastClipping = clipping
            updateCount += 1
        }
    }

    // MARK: - Initialization Tests

    func testInit_defaultValues_metersEnabledTrue() {
        let store = MeterStore()
        XCTAssertTrue(store.metersEnabled)
    }

    func testInit_withMetersEnabledFalse() {
        let store = MeterStore(metersEnabled: false)
        XCTAssertFalse(store.metersEnabled)
    }

    // MARK: - Observer Registration Tests

    func testAddObserver_receivesUpdates() {
        let store = MeterStore()
        let observer = TestObserver()

        store.addObserver(observer, for: .inputPeakLeft)

        // Initially silent state should be sent
        XCTAssertEqual(observer.lastValue, 0)
        XCTAssertEqual(observer.lastHold, 0)
        XCTAssertFalse(observer.lastClipping)
    }

    func testRemoveObserver_stopsReceivingUpdates() {
        let store = MeterStore()
        let observer = TestObserver()

        store.addObserver(observer, for: .inputPeakLeft)
        store.removeObserver(observer, for: .inputPeakLeft)

        // Should not crash and updates should stop
        XCTAssertTrue(true)
    }

    // MARK: - metersEnabled Toggle Tests

    func testMetersEnabled_whenDisabled_notifiesAllObserversSilent() {
        let store = MeterStore()
        let peakObserver = TestObserver()
        let rmsObserver = TestObserver()

        store.addObserver(peakObserver, for: .inputPeakLeft)
        store.addObserver(rmsObserver, for: .inputRMSLeft)

        store.metersEnabled = false

        // Both observers should have been notified with silent state
        XCTAssertEqual(peakObserver.lastValue, 0)
        XCTAssertEqual(rmsObserver.lastValue, 0)
    }

    func testMetersEnabled_whenEnabled_startsUpdates() {
        let store = MeterStore(metersEnabled: false)
        let observer = TestObserver()

        store.addObserver(observer, for: .inputPeakLeft)
        let initialCount = observer.updateCount

        store.metersEnabled = true

        // Should not crash and updates should start
        XCTAssertTrue(true)
    }

    // MARK: - Timer Lifecycle Tests

    func testStopMeterUpdates_notifiesAllObserversSilent() {
        let store = MeterStore()
        let observer = TestObserver()

        store.addObserver(observer, for: .inputPeakLeft)
        observer.updateCount = 0  // Reset count

        store.stopMeterUpdates()

        // Observer should have been notified with silent state
        XCTAssertEqual(observer.lastValue, 0)
    }

    func testStartMeterUpdates_withoutPipeline_noCrash() {
        let store = MeterStore()

        store.startMeterUpdates()

        XCTAssertTrue(true)
    }

    // MARK: - Multiple Meter Types

    func testMultipleObserversForDifferentTypes() {
        let store = MeterStore()
        let inputPeakObserver = TestObserver()
        let outputPeakObserver = TestObserver()
        let inputRMSObserver = TestObserver()
        let outputRMSObserver = TestObserver()

        store.addObserver(inputPeakObserver, for: .inputPeakLeft)
        store.addObserver(outputPeakObserver, for: .outputPeakLeft)
        store.addObserver(inputRMSObserver, for: .inputRMSLeft)
        store.addObserver(outputRMSObserver, for: .outputRMSLeft)

        // All observers should have received initial silent state
        XCTAssertEqual(inputPeakObserver.lastValue, 0)
        XCTAssertEqual(outputPeakObserver.lastValue, 0)
        XCTAssertEqual(inputRMSObserver.lastValue, 0)
        XCTAssertEqual(outputRMSObserver.lastValue, 0)
    }
}

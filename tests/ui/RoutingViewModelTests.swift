@testable import Equaliser
import XCTest
import SwiftUI

@MainActor
final class RoutingViewModelTests: XCTestCase {

    // MARK: - Status Color Tests

    func testStatusColor_idle_isSecondary() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusColor, .secondary)
    }

    func testStatusColor_starting_isSecondary() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .starting
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusColor, .secondary)
    }

    func testStatusColor_active_isGreen() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusColor, .green)
    }

    func testStatusColor_activeBypassed_isYellow() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusColor, .yellow)
    }

    func testStatusColor_driverNotInstalled_isOrange() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .driverNotInstalled
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusColor, .orange)
    }

    func testStatusColor_error_isRed() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Test error")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusColor, .red)
    }

    // MARK: - Status Background Color Tests

    func testStatusBackgroundColor_idle_isSecondaryOpacity() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.statusBackgroundColor)
    }

    func testStatusBackgroundColor_starting_isSecondaryOpacity() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .starting
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.statusBackgroundColor)
    }

    func testStatusBackgroundColor_active_isGreenOpacity() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.statusBackgroundColor)
    }

    func testStatusBackgroundColor_activeBypassed_isYellowOpacity() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.statusBackgroundColor)
    }

    func testStatusBackgroundColor_driverNotInstalled_isOrangeOpacity() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .driverNotInstalled
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.statusBackgroundColor)
    }

    func testStatusBackgroundColor_error_isRedOpacity() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Test error")
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.statusBackgroundColor)
    }

    // MARK: - Simplified Status Text Tests

    func testSimplifiedStatusText_idle_returnsIdle() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.simplifiedStatusText, "Idle")
    }

    func testSimplifiedStatusText_starting_returnsStarting() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .starting
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.simplifiedStatusText, "Starting...")
    }

    func testSimplifiedStatusText_active_returnsActive() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.simplifiedStatusText, "Active")
    }

    func testSimplifiedStatusText_activeBypassed_returnsBypassed() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.simplifiedStatusText, "Bypassed")
    }

    func testSimplifiedStatusText_driverNotInstalled_returnsNotInstalled() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .driverNotInstalled
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.simplifiedStatusText, "Not Installed")
    }

    func testSimplifiedStatusText_error_returnsError() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Test error")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.simplifiedStatusText, "Error")
    }

    // MARK: - Detailed Status Text Tests

    func testDetailedStatusText_idle_returnsStopped() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusText, "Audio Routing Stopped")
    }

    func testDetailedStatusText_starting_returnsStarting() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .starting
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusText, "Starting...")
    }

    func testDetailedStatusText_active_returnsWithEQ() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusText, "Mic → EQ → Speakers")
    }

    func testDetailedStatusText_activeBypassed_returnsWithoutEQ() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusText, "Mic → Speakers")
    }

    func testDetailedStatusText_driverNotInstalled_returnsInstallPrompt() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .driverNotInstalled
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusText, "Driver Not Installed - Open Settings to Install")
    }

    func testDetailedStatusText_error_returnsMessage() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Connection failed")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusText, "Connection failed")
    }

    // MARK: - Detailed Status Color Tests

    func testDetailedStatusColor_activeNotBypassed_isPrimary() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusColor, .primary)
    }

    func testDetailedStatusColor_activeBypassed_isYellow() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusColor, .yellow)
    }

    func testDetailedStatusColor_idle_isSecondary() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusColor, .secondary)
    }

    func testDetailedStatusColor_error_isRed() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Test error")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.detailedStatusColor, .red)
    }

    // MARK: - Status Text Styling Tests

    func testStatusTextIsMedium_activeNotBypassed_isTrue() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertTrue(vm.statusTextIsMedium)
    }

    func testStatusTextIsMedium_activeBypassed_isFalse() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.statusTextIsMedium)
    }

    func testStatusTextIsMedium_idle_isFalse() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.statusTextIsMedium)
    }

    func testStatusTextIsMedium_error_isFalse() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Test error")
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.statusTextIsMedium)
    }

    func testStatusTextLineLimit_error_returns2() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Test error")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusTextLineLimit, 2)
    }

    func testStatusTextLineLimit_idle_returnsNil() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertNil(vm.statusTextLineLimit)
    }

    func testStatusTextLineLimit_active_returnsNil() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertNil(vm.statusTextLineLimit)
    }

    // MARK: - Status Icon Tests

    func testStatusIconName_idle_returnsStopCircle() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusIconName, "stop.circle")
    }

    func testStatusIconName_starting_returnsNil() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .starting
        let vm = RoutingViewModel(store: store)

        XCTAssertNil(vm.statusIconName)
    }

    func testStatusIconName_active_returnsWaveform() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusIconName, "waveform.circle.fill")
    }

    func testStatusIconName_activeBypassed_returnsPauseCircle() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusIconName, "pause.circle.fill")
    }

    func testStatusIconName_driverNotInstalled_returnsSpeakerWave() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .driverNotInstalled
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusIconName, "speaker.wave.3.fill")
    }

    func testStatusIconName_error_returnsExclamation() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .error("Test error")
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusIconName, "exclamationmark.triangle.fill")
    }

    func testShowsProgressIndicator_starting_isTrue() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .starting
        let vm = RoutingViewModel(store: store)

        XCTAssertTrue(vm.showsProgressIndicator)
    }

    func testShowsProgressIndicator_idle_isFalse() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.showsProgressIndicator)
    }

    func testShowsProgressIndicator_active_isFalse() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.showsProgressIndicator)
    }

    func testStatusIconColor_matchesStatusBaseColor() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusIconColor, vm.statusColor)
    }

    func testStatusIconColor_activeBypassed_matchesStatusBaseColor() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.statusIconColor, vm.statusColor)
    }

    // MARK: - Toggle State Tests

    func testCanToggleRouting_automaticMode_returnsTrue() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertTrue(vm.canToggleRouting)
    }

    func testCanToggleRouting_manualModeWithDevices_returnsTrue() {
        let store = EqualiserStore()
        store.routingCoordinator.manualModeEnabled = true
        store.routingCoordinator.selectedInputDeviceID = "test-input-uid"
        store.routingCoordinator.selectedOutputDeviceID = "test-output-uid"
        let vm = RoutingViewModel(store: store)

        XCTAssertTrue(vm.canToggleRouting)
    }

    func testCanToggleRouting_manualModeWithoutInputDevice_returnsFalse() {
        let store = EqualiserStore()
        store.routingCoordinator.manualModeEnabled = true
        store.routingCoordinator.selectedInputDeviceID = nil
        store.routingCoordinator.selectedOutputDeviceID = "test-output-uid"
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.canToggleRouting)
    }

    func testCanToggleRouting_manualModeWithoutOutputDevice_returnsFalse() {
        let store = EqualiserStore()
        store.routingCoordinator.manualModeEnabled = true
        store.routingCoordinator.selectedInputDeviceID = "test-input-uid"
        store.routingCoordinator.selectedOutputDeviceID = nil
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.canToggleRouting)
    }

    func testCanToggleRouting_manualModeWithoutBothDevices_returnsFalse() {
        let store = EqualiserStore()
        store.routingCoordinator.manualModeEnabled = true
        store.routingCoordinator.selectedInputDeviceID = nil
        store.routingCoordinator.selectedOutputDeviceID = nil
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.canToggleRouting)
    }

    func testIsActive_initialState_returnsFalse() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.isActive)
    }

    func testIsActive_whenActive_returnsTrue() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vm = RoutingViewModel(store: store)

        XCTAssertTrue(vm.isActive)
    }

    // MARK: - Bypass State Tests

    func testIsBypassed_initialState_returnsFalse() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.isBypassed)
    }

    func testIsBypassed_whenSet_returnsTrue() {
        let store = EqualiserStore()
        store.isBypassed = true
        let vm = RoutingViewModel(store: store)

        XCTAssertTrue(vm.isBypassed)
    }

    func testIsBypassed_affectsStatusColor() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vmNotBypassed = RoutingViewModel(store: store)

        XCTAssertEqual(vmNotBypassed.statusColor, .green)

        store.isBypassed = true
        let vmBypassed = RoutingViewModel(store: store)

        XCTAssertEqual(vmBypassed.statusColor, .yellow)
    }

    func testIsBypassed_affectsSimplifiedStatusText() {
        let store = EqualiserStore()
        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        let vmNotBypassed = RoutingViewModel(store: store)

        XCTAssertEqual(vmNotBypassed.simplifiedStatusText, "Active")

        store.isBypassed = true
        let vmBypassed = RoutingViewModel(store: store)

        XCTAssertEqual(vmBypassed.simplifiedStatusText, "Bypassed")
    }

    // MARK: - Device Name Tests

    func testInputDeviceName_noSelection_returnsNone() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.inputDeviceName)
    }

    func testOutputDeviceName_noSelection_returnsNone() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.outputDeviceName)
    }

    // MARK: - Device Lists Tests

    func testInputDevices_emptyInitially_returnsEmpty() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.inputDevices)
    }

    func testOutputDevices_emptyInitially_returnsEmpty() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertNotNil(vm.outputDevices)
    }

    // MARK: - Mode State Tests

    func testManualModeEnabled_initialState_returnsFalse() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertFalse(vm.manualModeEnabled)
    }

    func testManualModeEnabled_whenSet_returnsTrue() {
        let store = EqualiserStore()
        store.routingCoordinator.manualModeEnabled = true
        let vm = RoutingViewModel(store: store)

        XCTAssertTrue(vm.manualModeEnabled)
    }

    // MARK: - Status Property Tests

    func testStatus_returnsRoutingStatus() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)

        XCTAssertEqual(vm.status, .idle)

        store.routingCoordinator.routingStatus = .active(inputName: "Mic", outputName: "Speakers")
        XCTAssertEqual(vm.status, .active(inputName: "Mic", outputName: "Speakers"))
    }
}
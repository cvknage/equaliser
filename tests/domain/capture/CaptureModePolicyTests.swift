// CaptureModePolicyTests.swift
// Tests for CaptureModePolicy pure functions

import XCTest
@testable import Equaliser

final class CaptureModePolicyTests: XCTestCase {
    
    // MARK: - Manual Mode
    
    func test_manualMode_alwaysUsesHALInput() {
        let decision = CaptureModePolicy.determineMode(
            preference: .sharedMemory,
            isManualMode: true,
            supportsSharedMemory: true
        )
        XCTAssertEqual(decision, .useMode(.halInput))
    }
    
    func test_manualMode_ignoresPreferenceAndCapability() {
        // Even if shared memory is preferred and available
        let decision = CaptureModePolicy.determineMode(
            preference: .sharedMemory,
            isManualMode: true,
            supportsSharedMemory: true
        )
        XCTAssertEqual(decision, .useMode(.halInput))
    }
    
    // MARK: - Automatic Mode - HAL Input Preference
    
    func test_halInputPreference_usesHALInput() {
        let decision = CaptureModePolicy.determineMode(
            preference: .halInput,
            isManualMode: false,
            supportsSharedMemory: true
        )
        XCTAssertEqual(decision, .useMode(.halInput))
    }
    
    func test_halInputPreference_ignoresCapability() {
        // HAL input doesn't care about shared memory capability
        let decision = CaptureModePolicy.determineMode(
            preference: .halInput,
            isManualMode: false,
            supportsSharedMemory: false
        )
        XCTAssertEqual(decision, .useMode(.halInput))
    }
    
    // MARK: - Automatic Mode - Shared Memory Preference
    
    func test_sharedMemoryPreference_withCapability_usesSharedMemory() {
        let decision = CaptureModePolicy.determineMode(
            preference: .sharedMemory,
            isManualMode: false,
            supportsSharedMemory: true
        )
        XCTAssertEqual(decision, .useMode(.sharedMemory))
    }
    
    func test_sharedMemoryPreference_withoutCapability_fallsBackToHAL() {
        let decision = CaptureModePolicy.determineMode(
            preference: .sharedMemory,
            isManualMode: false,
            supportsSharedMemory: false
        )
        XCTAssertEqual(decision, .fallbackToHALInput)
    }
    
    // MARK: - Edge Cases
    
    func test_automaticMode_halInput_noSharedMemory_usesHALInput() {
        // User chose HAL input explicitly, capability doesn't matter
        let decision = CaptureModePolicy.determineMode(
            preference: .halInput,
            isManualMode: false,
            supportsSharedMemory: false
        )
        XCTAssertEqual(decision, .useMode(.halInput))
    }
    
    func test_automaticMode_sharedMemory_available_usesSharedMemory() {
        // Happy path for shared memory
        let decision = CaptureModePolicy.determineMode(
            preference: .sharedMemory,
            isManualMode: false,
            supportsSharedMemory: true
        )
        XCTAssertEqual(decision, .useMode(.sharedMemory))
    }
}
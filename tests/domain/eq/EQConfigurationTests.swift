import XCTest
@testable import Equaliser

final class EQConfigurationTests: XCTestCase {
    // MARK: - Frequency Generation Tests

    @MainActor
    func testFrequenciesForBandCount_singleBand() {
        let frequencies = EQConfiguration.frequenciesForBandCount(1)

        XCTAssertEqual(frequencies.count, 1)
        XCTAssertEqual(frequencies[0], 20.0, accuracy: 0.001)
    }

    @MainActor
    func testFrequenciesForBandCount_twoBands() {
        let frequencies = EQConfiguration.frequenciesForBandCount(2)

        XCTAssertEqual(frequencies.count, 2)
        XCTAssertEqual(frequencies[0], 20.0, accuracy: 0.001)
        XCTAssertEqual(frequencies[1], 26000.0, accuracy: 0.001)
    }

    @MainActor
    func testFrequenciesForBandCount_logarithmicSpacing() {
        // Test logarithmic spacing for band counts that don't use standard frequencies
        // 10 bands uses standard frequencies: 32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000
        let bandCount = 10

        let frequencies = EQConfiguration.frequenciesForBandCount(bandCount)

        XCTAssertEqual(frequencies, [32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000])
    }

    @MainActor
    func testFrequenciesForBandCount_32bands() {
        let frequencies = EQConfiguration.frequenciesForBandCount(32)

        XCTAssertEqual(frequencies.count, 32)
        XCTAssertEqual(frequencies.first!, 20.0, accuracy: 0.001)
        XCTAssertEqual(frequencies.last!, 26000.0, accuracy: 1.0)

        // Verify frequencies are strictly increasing
        for i in 1..<frequencies.count {
            XCTAssertGreaterThan(frequencies[i], frequencies[i - 1], "Frequencies should be strictly increasing")
        }
    }

    @MainActor
    func testFrequenciesForBandCount_64bands() {
        let frequencies = EQConfiguration.frequenciesForBandCount(64)

        XCTAssertEqual(frequencies.count, 64)
        XCTAssertEqual(frequencies.first!, 20.0, accuracy: 0.001)
        XCTAssertEqual(frequencies.last!, 26000.0, accuracy: 1.0)

        // Calculate expected ratio for 64 bands
        let expectedRatio = pow(26000.0 / 20.0, 1.0 / Float(63))

        // Verify logarithmic spacing
        for i in 1..<frequencies.count {
            let actualRatio = frequencies[i] / frequencies[i - 1]
            XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.001)
        }
    }

    @MainActor
    func testFrequenciesForBandCount_allWithinRange() {
        for bandCount in [1, 2, 8, 16, 32, 64] {
            let frequencies = EQConfiguration.frequenciesForBandCount(bandCount)

            for (index, freq) in frequencies.enumerated() {
                XCTAssertGreaterThanOrEqual(freq, 20.0, "Band \(index) frequency \(freq) is below minimum")
                // Allow small floating-point tolerance above 26000
                XCTAssertLessThanOrEqual(freq, 26001.0, "Band \(index) frequency \(freq) is above maximum")
            }
        }
    }

    // MARK: - Band Count Clamping Tests

    @MainActor
    func testClampBandCount_boundaries() {
        // Lower boundary: 1
        XCTAssertEqual(EQConfiguration.clampBandCount(1), 1)

        // Upper boundary: 64
        XCTAssertEqual(EQConfiguration.clampBandCount(64), 64)

        // Mid-range values
        XCTAssertEqual(EQConfiguration.clampBandCount(32), 32)
        XCTAssertEqual(EQConfiguration.clampBandCount(16), 16)
    }

    @MainActor
    func testClampBandCount_invalidValues() {
        // Zero should clamp to 1
        XCTAssertEqual(EQConfiguration.clampBandCount(0), 1)

        // Negative values should clamp to 1
        XCTAssertEqual(EQConfiguration.clampBandCount(-1), 1)
        XCTAssertEqual(EQConfiguration.clampBandCount(-100), 1)

        // Values above 64 should clamp to 64
        XCTAssertEqual(EQConfiguration.clampBandCount(65), 64)
        XCTAssertEqual(EQConfiguration.clampBandCount(100), 64)
        XCTAssertEqual(EQConfiguration.clampBandCount(1000), 64)
    }

    func testClampBandCount_maxBandCountConstant() {
        // Verify maxBandCount is 64 as documented
        XCTAssertEqual(EQConfiguration.maxBandCount, 64)
    }

    func testClampBandCount_defaultBandCountConstant() {
        // Verify defaultBandCount is 10 as documented (standard 10-band EQ)
        XCTAssertEqual(EQConfiguration.defaultBandCount, 10)
    }

    // MARK: - EQConfiguration Instance Tests

    @MainActor
    func testInit_withDefaultBandCount() {
        let config = EQConfiguration()

        XCTAssertEqual(config.activeBandCount, EQConfiguration.defaultBandCount)
        XCTAssertEqual(config.bands.count, EQConfiguration.maxBandCount)
    }

    @MainActor
    func testInit_withCustomBandCount() {
        let config = EQConfiguration(initialBandCount: 16)

        XCTAssertEqual(config.activeBandCount, 16)
    }

    @MainActor
    func testInit_clampsInvalidBandCount() {
        // Band count too high
        let configHigh = EQConfiguration(initialBandCount: 100)
        XCTAssertEqual(configHigh.activeBandCount, 64)

        // Band count too low
        let configLow = EQConfiguration(initialBandCount: 0)
        XCTAssertEqual(configLow.activeBandCount, 1)
    }

    @MainActor
    func testSetActiveBandCount_clampsValue() {
        let config = EQConfiguration()

        let result = config.setActiveBandCount(100)
        XCTAssertEqual(result, 64)
        XCTAssertEqual(config.activeBandCount, 64)
    }

    func testDefaultBandwidth() {
        // Verify default bandwidth constant
        XCTAssertEqual(EQConfiguration.defaultBandwidth, 0.67)
    }

    // MARK: - Band Update Tests

    @MainActor
    func testUpdateBandGain() {
        let config = EQConfiguration(initialBandCount: 10)
        config.updateBandGain(index: 0, gain: 6.0)

        XCTAssertEqual(config.bands[0].gain, 6.0, accuracy: 0.001)
    }

    @MainActor
    func testUpdateBandFrequency() {
        let config = EQConfiguration(initialBandCount: 10)
        config.updateBandFrequency(index: 2, frequency: 500)

        XCTAssertEqual(config.bands[2].frequency, 500, accuracy: 0.001)
    }

    @MainActor
    func testUpdateBandBandwidth() {
        let config = EQConfiguration(initialBandCount: 10)
        config.updateBandBandwidth(index: 3, bandwidth: 1.5)

        XCTAssertEqual(config.bands[3].bandwidth, 1.5, accuracy: 0.001)
    }

    @MainActor
    func testUpdateBandBypass() {
        let config = EQConfiguration(initialBandCount: 10)
        XCTAssertFalse(config.bands[0].bypass)

        config.updateBandBypass(index: 0, bypass: true)
        XCTAssertTrue(config.bands[0].bypass)

        config.updateBandBypass(index: 0, bypass: false)
        XCTAssertFalse(config.bands[0].bypass)
    }

    @MainActor
    func testUpdateBandFilterType() {
        let config = EQConfiguration(initialBandCount: 10)
        config.updateBandFilterType(index: 1, filterType: .lowPass)

        XCTAssertEqual(config.bands[1].filterType, .lowPass)
    }

    @MainActor
    func testGlobalBypass() {
        let config = EQConfiguration()
        XCTAssertFalse(config.globalBypass)

        config.globalBypass = true
        XCTAssertTrue(config.globalBypass)
    }

    @MainActor
    func testInputOutputGain() {
        let config = EQConfiguration()
        XCTAssertEqual(config.inputGain, 0, accuracy: 0.001)
        XCTAssertEqual(config.outputGain, 0, accuracy: 0.001)

        config.inputGain = 6.0
        config.outputGain = -3.0

        XCTAssertEqual(config.inputGain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.outputGain, -3.0, accuracy: 0.001)
    }

    // MARK: - Active Band Count Tests

    @MainActor
    func testSetActiveBandCount_preservesConfiguredBands() {
        let config = EQConfiguration(initialBandCount: 10)
        // Modify some band gains
        config.updateBandGain(index: 0, gain: 6.0)
        config.updateBandGain(index: 5, gain: -3.0)

        // Increase band count (preserve configured bands)
        config.setActiveBandCount(16, preserveConfiguredBands: true)

        // Verify the original bands still have their settings
        XCTAssertEqual(config.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.bands[5].gain, -3.0, accuracy: 0.001)
        XCTAssertEqual(config.activeBandCount, 16)
    }

    @MainActor
    func testSetActiveBandCount_decreasingBandCount() {
        let config = EQConfiguration(initialBandCount: 32)
        // Modify some band gains
        config.updateBandGain(index: 0, gain: 6.0)
        config.updateBandGain(index: 5, gain: -3.0)

        // Decrease band count
        config.setActiveBandCount(10, preserveConfiguredBands: true)

        // Verify the original bands still have their settings
        XCTAssertEqual(config.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.bands[5].gain, -3.0, accuracy: 0.001)
        XCTAssertEqual(config.activeBandCount, 10)
    }

    @MainActor
    func testSetActiveBandCount_withoutPreserveRespreadsFrequencies() {
        let config = EQConfiguration(initialBandCount: 10)
        // Modify some band settings
        config.updateBandGain(index: 0, gain: 6.0)
        config.updateBandGain(index: 5, gain: -3.0)

        // Increase band count without preserving configured bands
        config.setActiveBandCount(16, preserveConfiguredBands: false)

        // Verify bands were reset (gain should be 0)
        XCTAssertEqual(config.bands[0].gain, 0, accuracy: 0.001)
        XCTAssertEqual(config.bands[5].gain, 0, accuracy: 0.001)
        XCTAssertEqual(config.activeBandCount, 16)
    }

    // MARK: - Channel Mode Tests

    @MainActor
    func testChannelMode_defaultIsLinked() {
        let config = EQConfiguration()
        XCTAssertEqual(config.channelMode, .linked)
    }

    @MainActor
    func testChannelMode_switchToStereoCopiesLeftToRight() {
        let config = EQConfiguration(initialBandCount: 10)

        // Modify left channel
        config.updateBandGain(index: 0, gain: 6.0)
        config.updateBandGain(index: 5, gain: -3.0)

        // Switch to stereo mode
        config.setChannelMode(.stereo)

        XCTAssertEqual(config.channelMode, .stereo)

        // Right channel should have same values as left
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[5].gain, -3.0, accuracy: 0.001)
    }

    @MainActor
    func testChannelMode_linkedModeUpdatesBothChannels() {
        let config = EQConfiguration(initialBandCount: 10)
        XCTAssertEqual(config.channelMode, .linked)  // Default is linked

        // Update gain in linked mode
        config.updateBandGain(index: 0, gain: 6.0)

        // Both channels should have the same value
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
    }

    @MainActor
    func testChannelMode_stereoModeUpdatesOnlyEditedChannel() {
        let config = EQConfiguration(initialBandCount: 10)
        config.setChannelMode(.stereo)
        config.editingChannel = .left

        // Update gain on left channel
        config.updateBandGain(index: 0, gain: 6.0)

        // Only left should be updated
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, 0, accuracy: 0.001)

        // Switch to right channel and update
        config.editingChannel = .right
        config.updateBandGain(index: 0, gain: -3.0)

        // Only right should be updated
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, -3.0, accuracy: 0.001)
    }

    @MainActor
    func testChannelMode_channelSpecificUpdate() {
        let config = EQConfiguration(initialBandCount: 10)
        config.setChannelMode(.stereo)

        // Update left channel specifically
        config.updateBandGain(index: 0, gain: 6.0, channel: .left)
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, 0, accuracy: 0.001)

        // Update right channel specifically
        config.updateBandGain(index: 0, gain: -3.0, channel: .right)
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, -3.0, accuracy: 0.001)

        // Update both channels
        config.updateBandGain(index: 0, gain: 0, channel: .both)
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, 0, accuracy: 0.001)
    }

    @MainActor
    func testChannelMode_linkedModeIgnoresChannelParameter() {
        let config = EQConfiguration(initialBandCount: 10)
        XCTAssertEqual(config.channelMode, .linked)  // Ensure linked

        // In linked mode, channel parameter is ignored - both channels updated
        config.updateBandGain(index: 0, gain: 6.0, channel: .left)

        // Both channels should have the same value despite specifying .left
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(config.rightState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
    }

    @MainActor
    func testChannelFocus_defaultIsLeft() {
        let config = EQConfiguration()
        XCTAssertEqual(config.editingChannel, .left)
    }

    // MARK: - Bands Property Tests

    @MainActor
    func testBands_linkedMode_returnsLeftChannel() {
        let config = EQConfiguration(initialBandCount: 10)
        config.updateBandGain(index: 0, gain: 6.0)

        // In linked mode, bands should return left channel
        XCTAssertEqual(config.channelMode, .linked)
        XCTAssertEqual(config.bands[0].gain, 6.0, accuracy: 0.001)
    }

    @MainActor
    func testBands_stereoMode_returnsEditedChannel() {
        let config = EQConfiguration(initialBandCount: 10)
        config.setChannelMode(.stereo)

        // Edit left channel
        config.editingChannel = .left
        config.updateBandGain(index: 0, gain: 6.0)

        // bands should return left channel gains
        XCTAssertEqual(config.bands[0].gain, 6.0, accuracy: 0.001)

        // Switch to editing right channel
        config.editingChannel = .right
        config.updateBandGain(index: 0, gain: -3.0)

        // bands should now return right channel gains
        XCTAssertEqual(config.bands[0].gain, -3.0, accuracy: 0.001)

        // Verify left channel is unchanged
        XCTAssertEqual(config.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
    }

    // MARK: - Snapshot Tests

    @MainActor
    func testSnapshot_roundtripPreservesState() {
        let config = EQConfiguration(initialBandCount: 10)
        config.globalBypass = true
        config.inputGain = 3.5
        config.outputGain = -2.0
        config.setChannelMode(.stereo)

        // Set different gains on each channel
        config.editingChannel = .left
        config.updateBandGain(index: 0, gain: 6.0)
        config.editingChannel = .right
        config.updateBandGain(index: 0, gain: -3.0)

        // Create snapshot
        let snapshot = AppStateSnapshot(
            globalBypass: config.globalBypass,
            inputGain: config.inputGain,
            outputGain: config.outputGain,
            channelMode: config.channelMode,
            channelFocus: config.editingChannel,
            leftState: config.leftState,
            rightState: config.rightState,
            inputDeviceID: nil,
            outputDeviceID: "test-device",
            bandwidthDisplayMode: "octaves",
            manualModeEnabled: false,
            captureMode: 0,
            metersEnabled: true
        )

        // Create new config from snapshot
        let restored = EQConfiguration(from: snapshot)

        // Verify restoration
        XCTAssertEqual(restored.globalBypass, true)
        XCTAssertEqual(restored.inputGain, 3.5, accuracy: 0.001)
        XCTAssertEqual(restored.outputGain, -2.0, accuracy: 0.001)
        XCTAssertEqual(restored.channelMode, .stereo)
        XCTAssertEqual(restored.editingChannel, .right)
        XCTAssertEqual(restored.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(restored.rightState.userEQ.bands[0].gain, -3.0, accuracy: 0.001)
    }

    @MainActor
    func testSnapshot_stereoModePreservesBothChannels() {
        let config = EQConfiguration(initialBandCount: 10)
        config.setChannelMode(.stereo)

        // Set different gains on each channel
        config.editingChannel = .left
        config.updateBandGain(index: 0, gain: 6.0)
        config.editingChannel = .right
        config.updateBandGain(index: 0, gain: -3.0)

        // Create snapshot
        let snapshot = AppStateSnapshot(
            globalBypass: false,
            inputGain: 0,
            outputGain: 0,
            channelMode: config.channelMode,
            channelFocus: config.editingChannel,
            leftState: config.leftState,
            rightState: config.rightState,
            inputDeviceID: nil,
            outputDeviceID: nil,
            bandwidthDisplayMode: "octaves",
            manualModeEnabled: false,
            captureMode: 0,
            metersEnabled: true
        )

        // Restore from snapshot
        let restored = EQConfiguration(from: snapshot)

        // Verify both channels preserved
        XCTAssertEqual(restored.leftState.userEQ.bands[0].gain, 6.0, accuracy: 0.001)
        XCTAssertEqual(restored.rightState.userEQ.bands[0].gain, -3.0, accuracy: 0.001)
        XCTAssertEqual(restored.channelMode, .stereo)
    }
}
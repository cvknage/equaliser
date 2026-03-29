// EQViewModel.swift
// Presentation logic for EQ configuration

import SwiftUI

/// View model for EQ band configuration UI.
/// Derives presentation state from EqualiserStore without containing business logic.
@MainActor
@Observable
final class EQViewModel {
    private unowned let store: EqualiserStore

    init(store: EqualiserStore) {
        self.store = store
    }

    // MARK: - Band Configuration

    /// Number of active EQ bands.
    var bandCount: Int {
        store.bandCount
    }

    /// All band configurations.
    var bands: [EQBandConfiguration] {
        store.eqConfiguration.bands
    }

    // MARK: - Channel Mode

    /// Current channel processing mode.
    var channelMode: ChannelMode {
        store.channelMode
    }

    /// Which channel is currently being edited (only meaningful in stereo mode).
    var channelFocus: ChannelFocus {
        get { store.channelFocus }
        set { store.channelFocus = newValue }
    }

    // MARK: - Gain State
    
    /// Input gain in dB.
    var inputGain: Float {
        get { store.inputGain }
        set { store.updateInputGain(newValue) }
    }
    
    /// Output gain in dB.
    var outputGain: Float {
        get { store.outputGain }
        set { store.updateOutputGain(newValue) }
    }
    
    // MARK: - Bypass State
    
    /// Whether System EQ is enabled (inverse of bypass).
    var isSystemEQEnabled: Bool {
        get { !store.isBypassed }
        set { store.isBypassed = !newValue }
    }
    
    /// Whether bypass is active.
    var isBypassed: Bool {
        get { store.isBypassed }
        set { store.isBypassed = newValue }
    }
    
    // MARK: - Compare Mode
    
    /// Current compare mode (EQ or Flat).
    var compareMode: CompareMode {
        get { store.compareMode }
        set { store.compareMode = newValue }
    }
    
    // MARK: - Formatted Display
    
    /// Formats a frequency value for display.
    /// - Parameter frequency: Frequency in Hz
    /// - Returns: Formatted string (e.g., "100 Hz", "1.5 kHz")
    func formattedFrequency(_ frequency: Float) -> String {
        if frequency >= 1000 {
            return String(format: "%.1f kHz", frequency / 1000)
        } else {
            return String(format: "%.0f Hz", frequency)
        }
    }
    
    /// Formats a gain value for display.
    /// - Parameter gain: Gain in dB
    /// - Returns: Formatted string (e.g., "+6.0 dB", "-3.0 dB")
    func formattedGain(_ gain: Float) -> String {
        gain >= 0 ? String(format: "+%.1f dB", gain) : String(format: "%.1f dB", gain)
    }
    
    /// Formats bandwidth for display based on user preference.
    /// - Parameters:
    ///   - bandwidth: Bandwidth in octaves
    ///   - mode: Display mode (octaves or Q)
    /// - Returns: Formatted string
    func formatBandwidth(_ bandwidth: Float, mode: BandwidthDisplayMode) -> String {
        switch mode {
        case .octaves:
            return String(format: "%.2f oct", bandwidth)
        case .qFactor:
            let q = BandwidthConverter.bandwidthToQ(bandwidth)
            return String(format: "Q %.2f", q)
        }
    }
    
    // MARK: - Band Actions
    
    /// Updates gain for a specific band.
    func updateBandGain(index: Int, gain: Float) {
        store.updateBandGain(index: index, gain: gain)
    }
    
    /// Updates frequency for a specific band.
    func updateBandFrequency(index: Int, frequency: Float) {
        store.updateBandFrequency(index: index, frequency: frequency)
    }
    
    /// Updates bandwidth for a specific band.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        store.updateBandBandwidth(index: index, bandwidth: bandwidth)
    }
    
    /// Updates filter type for a specific band.
    func updateBandFilterType(index: Int, filterType: FilterType) {
        store.updateBandFilterType(index: index, filterType: filterType)
    }
    
    /// Updates bypass state for a specific band.
    func updateBandBypass(index: Int, bypass: Bool) {
        store.updateBandBypass(index: index, bypass: bypass)
    }
    
    // MARK: - Global Actions
    
    /// Sets the number of active bands.
    func setBandCount(_ count: Int) {
        store.updateBandCount(count)
    }
    
    /// Flattens all bands (resets gains to 0).
    func flattenBands() {
        store.flattenBands()
    }
}
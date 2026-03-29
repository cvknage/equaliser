import AppKit
import AVFoundation
import Foundation
import os.log

struct AppStateSnapshot: Sendable {
    // MARK: - EQ Configuration

    var globalBypass: Bool
    var inputGain: Float
    var outputGain: Float

    /// Channel processing mode.
    var channelMode: ChannelMode

    /// Which channel is being edited in stereo mode.
    var channelFocus: ChannelFocus

    /// Left channel EQ state (also used for linked mode).
    var leftState: ChannelEQState

    /// Right channel EQ state (only used in stereo mode).
    var rightState: ChannelEQState

    // MARK: - App State

    var inputDeviceID: String?
    var outputDeviceID: String?
    var bandwidthDisplayMode: String
    var manualModeEnabled: Bool
    var captureMode: Int  // CaptureMode.rawValue

    // MARK: - Meter State

    var metersEnabled: Bool

    // MARK: - Defaults

    static var `default`: AppStateSnapshot {
        AppStateSnapshot(
            globalBypass: false,
            inputGain: 0,
            outputGain: 0,
            channelMode: .linked,
            channelFocus: .left,
            leftState: .default(),
            rightState: .default(),
            inputDeviceID: nil,
            outputDeviceID: nil,
            bandwidthDisplayMode: BandwidthDisplayMode.octaves.rawValue,
            manualModeEnabled: false,
            captureMode: CaptureMode.sharedMemory.rawValue,
            metersEnabled: true
        )
    }
}

// MARK: - Codable with Legacy Migration

extension AppStateSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case globalBypass
        case inputGain
        case outputGain
        case channelMode
        case channelFocus
        case editingChannel  // Legacy key for backward compatibility
        case leftState
        case rightState
        // Legacy keys for backward compatibility
        case activeBandCount
        case bands
        case rightBands
        // App state keys
        case inputDeviceID
        case outputDeviceID
        case bandwidthDisplayMode
        case manualModeEnabled
        case captureMode
        case metersEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // EQ configuration
        globalBypass = try container.decode(Bool.self, forKey: .globalBypass)
        inputGain = try container.decode(Float.self, forKey: .inputGain)
        outputGain = try container.decode(Float.self, forKey: .outputGain)

        // Channel mode: try new enum, fall back to legacy string
        if let mode = try container.decodeIfPresent(ChannelMode.self, forKey: .channelMode) {
            channelMode = mode
        } else if let modeString = try container.decodeIfPresent(String.self, forKey: .channelMode) {
            channelMode = ChannelMode(rawValue: modeString) ?? .linked
        } else {
            channelMode = .linked
        }

        // Channel focus: defaults to left
        // Try new key first, then fall back to legacy key for backward compatibility
        if let channel = try container.decodeIfPresent(ChannelFocus.self, forKey: .channelFocus) {
            channelFocus = channel
        } else if let channel = try container.decodeIfPresent(ChannelFocus.self, forKey: .editingChannel) {
            // Legacy key support
            channelFocus = channel
        } else {
            channelFocus = .left
        }

        // Try new format first (leftState/rightState)
        if let left = try container.decodeIfPresent(ChannelEQState.self, forKey: .leftState),
           let right = try container.decodeIfPresent(ChannelEQState.self, forKey: .rightState) {
            leftState = left
            rightState = right
        } else {
            // Migrate from legacy format (bands/rightBands/activeBandCount)
            let legacyBandCount = try container.decodeIfPresent(Int.self, forKey: .activeBandCount)
                ?? EQConfiguration.defaultBandCount
            let legacyBands = try container.decodeIfPresent([EQBandConfiguration].self, forKey: .bands)
            let legacyRightBands = try container.decodeIfPresent([EQBandConfiguration].self, forKey: .rightBands)

            // Build left state from legacy bands or default
            if let bands = legacyBands, bands.count == EQConfiguration.maxBandCount {
                var leftLayer = EQLayerState.userEQ(bandCount: legacyBandCount)
                leftLayer.bands = bands
                leftState = ChannelEQState(layers: [leftLayer])
            } else {
                leftState = .default(bandCount: legacyBandCount)
            }

            // Build right state from legacy rightBands or copy left
            if let rightBands = legacyRightBands, rightBands.count == EQConfiguration.maxBandCount {
                var rightLayer = EQLayerState.userEQ(bandCount: legacyBandCount)
                rightLayer.bands = rightBands
                rightState = ChannelEQState(layers: [rightLayer])
            } else {
                rightState = leftState
            }
        }

        // App state
        inputDeviceID = try container.decodeIfPresent(String.self, forKey: .inputDeviceID)
        outputDeviceID = try container.decodeIfPresent(String.self, forKey: .outputDeviceID)
        bandwidthDisplayMode = try container.decodeIfPresent(String.self, forKey: .bandwidthDisplayMode)
            ?? BandwidthDisplayMode.octaves.rawValue
        manualModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .manualModeEnabled) ?? false
        captureMode = try container.decodeIfPresent(Int.self, forKey: .captureMode)
            ?? CaptureMode.sharedMemory.rawValue
        metersEnabled = try container.decodeIfPresent(Bool.self, forKey: .metersEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode new format only (no legacy fields)
        try container.encode(globalBypass, forKey: .globalBypass)
        try container.encode(inputGain, forKey: .inputGain)
        try container.encode(outputGain, forKey: .outputGain)
        try container.encode(channelMode, forKey: .channelMode)
        try container.encode(channelFocus, forKey: .channelFocus)
        try container.encode(leftState, forKey: .leftState)
        try container.encode(rightState, forKey: .rightState)

        // App state
        try container.encodeIfPresent(inputDeviceID, forKey: .inputDeviceID)
        try container.encodeIfPresent(outputDeviceID, forKey: .outputDeviceID)
        try container.encode(bandwidthDisplayMode, forKey: .bandwidthDisplayMode)
        try container.encode(manualModeEnabled, forKey: .manualModeEnabled)
        try container.encode(captureMode, forKey: .captureMode)
        try container.encode(metersEnabled, forKey: .metersEnabled)
    }
}

@MainActor
final class AppStatePersistence {
    private let storage: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private weak var store: EqualiserStore?
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "AppStatePersistence")

    private enum Keys {
        static let appState = "equalizer.appState"
    }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        encoder.outputFormatting = [.sortedKeys]

        // Subscribe to app quit notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    func setStore(_ store: EqualiserStore) {
        self.store = store
    }

    func load() -> AppStateSnapshot? {
        guard let data = storage.data(forKey: Keys.appState) else { return nil }
        do {
            return try decoder.decode(AppStateSnapshot.self, from: data)
        } catch {
            logger.error("Failed to decode app state: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ snapshot: AppStateSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            storage.set(data, forKey: Keys.appState)
            logger.debug("Saved app state successfully")
        } catch {
            logger.error("Failed to encode app state: \(error.localizedDescription)")
        }
    }

    @objc private func handleAppWillTerminate(_ notification: Notification) {
        guard let store = store else { return }
        save(store.currentSnapshot)
        logger.info("Saved app state on quit")
    }
}
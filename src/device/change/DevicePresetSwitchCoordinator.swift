// DevicePresetSwitchCoordinator.swift
// Automatically applies per-device EQ presets when the output device changes

import Combine
import Foundation
import OSLog

/// Coordinates automatic per-device EQ preset switching.
///
/// ## Responsibilities
/// - Apply the mapped preset when the output device changes
/// - Remember which preset is active on the current device
///
/// ## Usage
/// The parent coordinator wires preset application:
/// ```swift
/// coordinator.onApplyPreset = { [weak self] name in
///     self?.loadPreset(named: name)
/// }
/// coordinator.autoApplyEnabledProvider = { [weak self] in
///     self?.autoApplyDevicePresets ?? true
/// }
/// ```
@MainActor
final class DevicePresetSwitchCoordinator {

    // MARK: - Event Callbacks

    /// Called when the mapped preset for a device should be applied.
    /// Parent coordinator loads the preset by name.
    var onApplyPreset: ((String) -> Void)?

    /// Returns whether automatic switching is currently enabled.
    /// Falls back to true when unset.
    var autoApplyEnabledProvider: (() -> Bool) = { true }

    // MARK: - Dependencies

    private let routingCoordinator: AudioRoutingCoordinator
    private let presetManager: PresetManager
    private let mappingService: DevicePresetMappingService

    // MARK: - State

    /// The device currently active when a preset is selected.
    private var currentDeviceUID: String?

    /// The preset most recently auto-applied, keyed by device.
    /// Skipped when it later surfaces via the preset stream (async delivery
    /// makes a synchronous in-flight flag unreliable at the sink).
    private var lastAutoApplied: (device: String, name: String)?

    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DevicePresetSwitchCoordinator")

    // MARK: - Initialization

    init(
        routingCoordinator: AudioRoutingCoordinator,
        presetManager: PresetManager,
        mappingService: DevicePresetMappingService
    ) {
        self.routingCoordinator = routingCoordinator
        self.presetManager = presetManager
        self.mappingService = mappingService
        setupSubscriptions()
    }

    // MARK: - Private Methods

    private func setupSubscriptions() {
        routingCoordinator.$selectedOutputDeviceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceUID in
                self?.handleOutputDeviceChanged(deviceUID)
            }
            .store(in: &cancellables)

        presetManager.$selectedPresetName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presetName in
                self?.handlePresetSelected(presetName)
            }
            .store(in: &cancellables)
    }

    /// Applies the mapped preset when the output device actually changes.
    private func handleOutputDeviceChanged(_ newUID: String?) {
        let oldUID = currentDeviceUID
        currentDeviceUID = newUID

        // Only act on a real change (skips same-device reassignments)
        guard newUID != oldUID,
              newUID != DRIVER_DEVICE_UID,
              let uid = newUID,
              autoApplyEnabledProvider() else {
            return
        }

        var map = mappingService.load()
        guard let presetName = map.presetFor(device: uid) else { return }

        // Prune stale mappings whose preset was deleted
        guard presetManager.preset(named: presetName) != nil else {
            map.remove(device: uid)
            mappingService.save(map)
            logger.info("Pruned preset mapping for removed preset '\(presetName)'")
            return
        }

        logger.info("Applying preset '\(presetName)' for output device change")
        lastAutoApplied = (device: uid, name: presetName)
        onApplyPreset?(presetName)
    }

    /// Records the preset chosen on the current device.
    private func handlePresetSelected(_ presetName: String?) {
        defer { lastAutoApplied = nil }
        guard autoApplyEnabledProvider(),
              let presetName = presetName,
              let uid = currentDeviceUID,
              uid != DRIVER_DEVICE_UID else {
            return
        }

        // Ignore the preset we just applied ourselves on the same device
        if let auto = lastAutoApplied, auto.device == uid, auto.name == presetName {
            return
        }

        var map = mappingService.load()
        map.record(device: uid, presetName: presetName)
        mappingService.save(map)
        logger.debug("Remembered preset '\(presetName)' for device \(uid)")
    }
}
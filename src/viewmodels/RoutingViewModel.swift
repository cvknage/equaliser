// RoutingViewModel.swift
// Presentation logic for routing status and device selection

import SwiftUI

/// View model for routing status display.
/// Derives presentation state from EqualiserStore without containing business logic.
@MainActor
@Observable
final class RoutingViewModel {
    private unowned let store: EqualiserStore
    
    init(store: EqualiserStore) {
        self.store = store
    }
    
    // MARK: - Status Display
    
    /// Color for status indicator based on routing state.
    var statusColor: Color {
        switch store.routingStatus {
        case .idle:
            return .gray
        case .starting:
            return .yellow
        case .active:
            return .green
        case .driverNotInstalled:
            return .orange
        case .error:
            return .red
        }
    }
    
    /// Human-readable status text for display.
    var statusText: String {
        switch store.routingStatus {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting..."
        case .active(let input, let output):
            return "\(input) → \(output)"
        case .driverNotInstalled:
            return "Driver Not Installed"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    /// Whether routing is currently active.
    var isActive: Bool {
        store.routingStatus.isActive
    }
    
    /// Whether routing can be toggled (started/stopped).
    var canToggleRouting: Bool {
        if store.manualModeEnabled {
            return store.selectedInputDeviceID != nil 
                && store.selectedOutputDeviceID != nil
        }
        return true // Automatic mode handles device selection
    }
    
    // MARK: - Device Display
    
    /// Formatted input device name for display.
    var inputDeviceName: String {
        guard let uid = store.selectedInputDeviceID,
              let device = store.inputDevices.first(where: { $0.uid == uid }) else {
            return "None"
        }
        return device.displayName
    }
    
    /// Formatted output device name for display.
    var outputDeviceName: String {
        guard let uid = store.selectedOutputDeviceID,
              let device = store.outputDevices.first(where: { $0.uid == uid }) else {
            return "None"
        }
        return device.displayName
    }
    
    /// Available input devices for picker.
    var inputDevices: [AudioDevice] {
        store.inputDevices
    }
    
    /// Available output devices for picker.
    var outputDevices: [AudioDevice] {
        store.outputDevices
    }
    
    /// Currently selected input device UID.
    var selectedInputDeviceID: String? {
        store.selectedInputDeviceID
    }
    
    /// Currently selected output device UID.
    var selectedOutputDeviceID: String? {
        store.selectedOutputDeviceID
    }
    
    // MARK: - Mode State
    
    /// Whether manual mode is enabled.
    var manualModeEnabled: Bool {
        store.manualModeEnabled
    }
    
    /// Whether driver prompt should be shown.
    var showDriverPrompt: Bool {
        store.showDriverPrompt
    }
    
    // MARK: - Actions
    
    /// Toggles routing on/off.
    func toggleRouting() {
        if store.routingStatus.isActive {
            store.stopRouting()
        } else {
            store.reconfigureRouting()
        }
    }
    
    /// Selects an input device.
    func selectInputDevice(_ uid: String?) {
        store.selectedInputDeviceID = uid
    }
    
    /// Selects an output device.
    func selectOutputDevice(_ uid: String?) {
        store.selectedOutputDeviceID = uid
    }
    
    /// Handles driver installation completion.
    func handleDriverInstalled() {
        store.handleDriverInstalled()
    }
    
    /// Switches to manual mode.
    func switchToManualMode() {
        store.switchToManualMode()
    }
}
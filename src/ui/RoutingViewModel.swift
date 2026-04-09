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

    /// Base color for routing status (shared by menu bar and status view).
    /// Returns semantic colors that work in both light and dark mode.
    private var statusBaseColor: Color {
        switch store.routingStatus {
        case .idle, .starting:
            return .secondary
        case .active:
            return store.isBypassed ? .yellow : .green
        case .driverNotInstalled:
            return .orange
        case .error:
            return .red
        }
    }

    /// Color for status indicator (used by MenuBarView).
    var statusColor: Color {
        statusBaseColor
    }

    /// Simplified status text for compact displays (menu bar).
    var simplifiedStatusText: String {
        switch store.routingStatus {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting..."
        case .active:
            return store.isBypassed ? "Bypassed" : "Active"
        case .driverNotInstalled:
            return "Not Installed"
        case .error:
            return "Error"
        }
    }
    
    /// Whether routing is currently active.
    var isActive: Bool {
        store.routingStatus.isActive
    }

    /// The routing status for display purposes.
    var status: RoutingStatus {
        store.routingStatus
    }

    /// Whether the EQ is bypassed.
    var isBypassed: Bool {
        store.isBypassed
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

    // MARK: - Detailed Status Display (RoutingStatusView)

    /// Detailed status text for the EQ window status bar.
    /// Includes device names and EQ indicator for active routing.
    var detailedStatusText: String {
        switch store.routingStatus {
        case .idle:
            return "Audio Routing Stopped"
        case .starting:
            return "Starting..."
        case .active(let input, let output):
            if store.isBypassed {
                return "\(input) → \(output)"
            }
            return "\(input) → EQ → \(output)"
        case .driverNotInstalled:
            return "Driver Not Installed - Open Settings to Install"
        case .error(let message):
            return message
        }
    }

    /// Status text color for detailed display.
    /// Uses .primary for active (not bypassed) to make text stand out.
    var detailedStatusColor: Color {
        switch store.routingStatus {
        case .active where !store.isBypassed:
            return .primary
        default:
            return statusBaseColor
        }
    }

    /// Whether status text should use medium font weight.
    var statusTextIsMedium: Bool {
        store.routingStatus.isActive && !store.isBypassed
    }

    /// Whether status text should have line limit (for error case).
    var statusTextLineLimit: Int? {
        switch store.routingStatus {
        case .error:
            return 2
        default:
            return nil
        }
    }

    /// Background color for the status bar.
    var statusBackgroundColor: Color {
        switch store.routingStatus {
        case .idle, .starting:
            return Color.secondary.opacity(0.1)
        case .active:
            return store.isBypassed ? Color.yellow.opacity(0.1) : Color.green.opacity(0.1)
        case .driverNotInstalled:
            return Color.orange.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        }
    }

    /// SF Symbol name for the status icon, if any.
    var statusIconName: String? {
        switch store.routingStatus {
        case .idle:
            return "stop.circle"
        case .starting:
            return nil // Uses ProgressView instead
        case .active:
            return store.isBypassed ? "pause.circle.fill" : "waveform.circle.fill"
        case .driverNotInstalled:
            return "speaker.wave.3.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    /// Whether to show a progress indicator instead of an icon.
    var showsProgressIndicator: Bool {
        store.routingStatus == .starting
    }

    /// Icon color for the status icon.
    var statusIconColor: Color {
        statusBaseColor
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
}
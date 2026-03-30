import SwiftUI

/// Tab identifier for Settings window.
enum SettingsTab: String {
    case display = "display"
    case driver = "driver"
}

struct SettingsView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var selectedTab: SettingsTab = .display
    
    /// Allows programmatic selection of tab (e.g., to show Driver tab when update required).
    var initialTab: SettingsTab? {
        if store.showDriverUpdateRequired {
            return .driver
        }
        return nil
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DisplaySettingsTab()
                .tabItem {
                    Label("Display", systemImage: "paintbrush")
                }
                .tag(SettingsTab.display)
            
            DriverSettingsTab()
                .tabItem {
                    Label("Driver", systemImage: "speaker.wave.3")
                }
                .tag(SettingsTab.driver)
        }
        .frame(width: 450, height: 400)
        .onAppear {
            // Auto-select Driver tab if update required
            if let initialTab = initialTab {
                selectedTab = initialTab
                // Clear the flag so user doesn't get forced back on subsequent opens
                store.clearDriverUpdateRequired()
            }
        }
    }
}

struct DisplaySettingsTab: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var showDriverRequiredAlert = false
    @State private var showPermissionDeniedAlert = false

    private enum Mode {
        case automatic
        case manual
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        Picker("Mode", selection: Binding(
                            get: { store.manualModeEnabled ? Mode.manual : Mode.automatic },
                            set: { newValue in
                                switch newValue {
                                case .automatic:
                                    if !DriverManager.shared.isReady {
                                        showDriverRequiredAlert = true
                                        return
                                    }
                                    store.switchToAutomaticMode()
                                case .manual:
                                    Task {
                                        let granted = await store.switchToManualMode()
                                        if !granted {
                                            showPermissionDeniedAlert = true
                                        }
                                    }
                                }
                            }
                        )) {
                            Text("Automatic").tag(Mode.automatic)
                            Text("Manual").tag(Mode.manual)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic mode (recommended):")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("App manages device selection automatically")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Works with macOS Sound settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manual mode:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("You choose input and output devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Requires microphone permission")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Device Selection Mode")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        Picker("Format", selection: $store.bandwidthDisplayMode) {
                            ForEach(BandwidthDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Q Factor:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Bandwidth as precision value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Higher = narrower, more surgical")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Octaves:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Bandwidth as musical intervals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Higher = wider frequency range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Bandwidth Display")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Driver Required", isPresented: $showDriverRequiredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Automatic mode requires the virtual audio driver. Please install it from the Driver tab in Settings.")
        }
        .alert("Permission Required", isPresented: $showPermissionDeniedAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Manual mode requires microphone permission.\n\nOpen System Settings to enable it.")
        }
    }
}

struct DriverSettingsTab: View {
    @EnvironmentObject var store: EqualiserStore
    @StateObject private var driverManager = DriverManager.shared
    @State private var showUninstallConfirm = false
    @State private var showHALPermissionDeniedAlert = false
    
    /// Whether the driver lacks shared memory capability
    private var driverNeedsUpdate: Bool {
        driverManager.isReady && !driverManager.hasSharedMemoryCapability()
    }
    
    var body: some View {
        Form {
            Section {
                contentView
            } header: {
                Text("Virtual Audio Driver")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        Picker("Method", selection: Binding(
                            get: { store.effectiveCaptureMode },
                            set: { newMode in
                                if newMode == .halInput {
                                    Task {
                                        let granted = await store.requestMicPermissionAndSwitchToHALCapture()
                                        if !granted {
                                            await MainActor.run {
                                                showHALPermissionDeniedAlert = true
                                            }
                                        }
                                    }
                                } else {
                                    store.captureMode = newMode
                                }
                            }
                        )) {
                            Text("Shared Memory").tag(CaptureMode.sharedMemory)
                            Text("HAL Input").tag(CaptureMode.halInput)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(store.manualModeEnabled)
                        .opacity(store.manualModeEnabled ? 0.5 : 1.0)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shared Memory (recommended):")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("No microphone permission required")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("No indicator in Control Center")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("HAL Input:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Requires microphone permission")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Shows microphone indicator")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Capture Mode")
            } footer: {
                if store.manualModeEnabled {
                    Text("Capture mode is not available in manual mode.")
                } else if driverNeedsUpdate {
                    Text("Using HAL Input because your driver version doesn't support shared memory. Update the driver to enable this feature.")
                }
            }
            
            Section {
                if driverManager.isInstalling {
                    HStack {
                        Spacer()
                        ProgressView("Please wait...")
                        Spacer()
                    }
                }
                
                if let error = driverManager.installError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                        Spacer()
                        Button {
                            driverManager.installError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Uninstall Driver", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) {
                Task {
                    do {
                        try await driverManager.uninstallDriver()
                    } catch {
                        driverManager.installError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("This will remove the Equaliser virtual audio driver from your system. You may need to restart coreaudiod.")
        }
        .alert("Permission Required", isPresented: $showHALPermissionDeniedAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("HAL Input capture requires microphone permission.\n\nOpen System Settings to enable it.")
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch driverManager.status {
        case .notInstalled:
            notInstalledView
        case .installed(let version):
            installedView(version: version)
        case .needsUpdate(let current, let bundled):
            needsUpdateView(current: current, bundled: bundled)
        case .error(let message):
            errorView(message: message)
        }
    }
    
    private var notInstalledView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Driver not installed")
                    .fontWeight(.medium)
            }
            
            Text("Install the driver to route audio through the equaliser.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Install Driver") {
                Task {
                    do {
                        try await driverManager.installDriver()
                    } catch {
                        driverManager.installError = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(driverManager.isInstalling)
        }
    }
    
    private func installedView(version: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Driver installed")
                    .fontWeight(.medium)
                Spacer()
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let sampleRate = driverManager.driverSampleRate {
                HStack {
                    Text("Sample Rate")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(sampleRate).formatted()) Hz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("The driver is ready to use.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Uninstall", role: .destructive) {
                showUninstallConfirm = true
            }
            .disabled(driverManager.isInstalling)
            .buttonStyle(.bordered)
        }
    }
    
    private func needsUpdateView(current: String, bundled: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                Text("Update available")
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 8) {
                Text("Current: v\(current)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("→")
                    .foregroundStyle(.secondary)
                Text("v\(bundled)")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            // Dynamic message based on version
            Text(updateMessage(for: current))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("Update Driver") {
                    Task {
                        do {
                            try await driverManager.installDriver()
                        } catch {
                            driverManager.installError = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(driverManager.isInstalling)
                
                Button("Uninstall", role: .destructive) {
                    showUninstallConfirm = true
                }
                .disabled(driverManager.isInstalling)
            }
        }
    }
    
    /// Minimum driver version that supports shared memory capture.
    private static let sharedMemoryMinVersion = "1.1.0"
    
    /// Returns the appropriate update message based on the installed version.
    /// Versions below 1.1.0 don't support shared memory capture.
    private func updateMessage(for currentVersion: String) -> String {
        if currentVersion < Self.sharedMemoryMinVersion {
            return "The current installed version does not support the \"Shared Memory\" capture mode.\nUpdate for improved audio routing without requiring microphone permission."
        } else {
            return "A newer version is available. Update to get the latest features and fixes."
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title)
            
            Text("Error")
                .fontWeight(.medium)
                .foregroundStyle(.red)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                driverManager.checkInstallationStatus()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

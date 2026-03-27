import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: EqualiserStore
    
    var body: some View {
        TabView {
            DisplaySettingsTab()
                .tabItem {
                    Label("Display", systemImage: "paintbrush")
                }
            
            DriverSettingsTab()
                .tabItem {
                    Label("Driver", systemImage: "speaker.wave.3")
                }
        }
        .frame(width: 450, height: 400)
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
                                // Manual mode uses HAL input, requires microphone permission
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

                if store.manualModeEnabled {
                    Text("You have full control over input and output device selection. Use this mode when integrating Equaliser into a custom audio chain with other applications, or when you want precise control over audio routing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Equaliser automatically configures itself based on your output device selection in macOS Sound settings. This is the recommended mode for most users.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Device Selection Mode")
            }

            Section("Bandwidth Display") {
                Picker("Format", selection: $store.bandwidthDisplayMode) {
                    ForEach(BandwidthDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Choose how bandwidth is displayed. \nOctaves: think \"how wide?\" — bigger numbers affect more frequencies. \nQ Factor: think \"how precise?\" — higher values are more surgical.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                
                Divider()
                
                contentView

                if driverManager.isInstalling {
                    ProgressView("Please wait...")
                        .padding()
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
                    .padding()
                }
            }
            .padding()
        }
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
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            
            Text("Virtual Audio Driver")
                .font(.headline)
            
            Text("Equaliser includes a built-in virtual audio driver for routing system audio through the equaliser.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch driverManager.status {
        case .notInstalled:
            notInstalledView
        case .installed(let version):
            VStack(spacing: 20) {
                installedView(version: version)

                // Capture mode settings (only in automatic mode)
                if !store.manualModeEnabled {
                    Divider()
                    captureModeSection
                }
            }
        case .needsUpdate(let current, let bundled):
            needsUpdateView(current: current, bundled: bundled)
        case .error(let message):
            errorView(message: message)
        }
    }

    @ViewBuilder
    private var captureModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture Mode")
                .font(.headline)

            Picker("Method", selection: Binding(
                get: { store.captureMode },
                set: { newMode in
                    if newMode == .halInput {
                        // Switching to HAL capture - request permission first
                        Task {
                            let granted = await store.requestMicPermissionAndSwitchToHALCapture()
                            if !granted {
                                // Permission denied - show alert
                                await MainActor.run {
                                    showHALPermissionDeniedAlert = true
                                }
                            }
                        }
                    } else {
                        // Switching to shared memory - no permission needed
                        store.captureMode = newMode
                    }
                }
            )) {
                Text("Shared Memory (no mic indicator)").tag(CaptureMode.sharedMemory)
                Text("HAL Input (requires permission)").tag(CaptureMode.halInput)
            }
            .pickerStyle(.radioGroup)

            if store.captureMode == .sharedMemory {
                Text("Audio is captured via shared memory. No microphone permission required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Audio is captured via HAL input. Microphone permission required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
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
            
            Text("A newer version is available. Update to get the latest features and fixes.")
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

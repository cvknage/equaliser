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
    
    var body: some View {
        Form {
            Section("Device Selection Mode") {
                Toggle("Manual Device Selection", isOn: Binding(
                    get: { store.manualModeEnabled },
                    set: { newValue in
                        if !newValue {
                            // Switching to automatic mode - check if driver is installed
                            if !DriverManager.shared.isReady {
                                showDriverRequiredAlert = true
                                return
                            }
                            store.switchToAutomaticMode()
                        } else {
                            store.switchToManualMode()
                        }
                    }
                ))
                
                Text(store.manualModeEnabled
                    ? "Manually select input and output devices. macOS Sound settings will not be changed."
                    : "Devices are automatically derived from macOS Sound output selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Bandwidth Display") {
                Picker("Format", selection: $store.bandwidthDisplayMode) {
                    ForEach(BandwidthDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Driver Required", isPresented: $showDriverRequiredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Automatic mode requires the virtual audio driver. Please install it from the Driver tab in Settings.")
        }
    }
}

struct DriverSettingsTab: View {
    @ObservedObject private var driverManager = DriverManager.shared
    @State private var showUninstallConfirm = false
    @State private var isRefreshing = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                
                Divider()
                
                contentView
                
                // Refresh button
                Button {
                    isRefreshing = true
                    driverManager.checkInstallationStatus()
                    // Delay to allow status update
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isRefreshing = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Status")
                    }
                }
                .disabled(driverManager.isInstalling || isRefreshing)
                
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
            
            Text("Install the driver to route audio through the equaliser without third-party tools.")
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
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text("Sample Rate: \(Int(sampleRate).formatted()) Hz")
                        .font(.callout)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            
            Text("The driver is ready. Select \"Equaliser\" as your input device to route audio through the equaliser.")
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

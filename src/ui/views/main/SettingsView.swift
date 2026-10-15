import SwiftUI

/// Tab identifier for Settings window.
enum SettingsTab: String {
    case display = "display"
    case driver = "driver"
    case about = "about"
}

struct SettingsView: View {
    @EnvironmentObject var store: EqualiserStore
    @EnvironmentObject var windowActivation: WindowActivationController
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

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 450, height: 400)
        .onAppear {
            windowActivation.windowBecameVisible(.settings)

            // Auto-select Driver tab if update required
            if let initialTab = initialTab {
                selectedTab = initialTab
                // Clear the flag so user doesn't get forced back on subsequent opens
                store.clearDriverUpdateRequired()
            }
        }
        .onDisappear {
            windowActivation.windowBecameHidden(.settings)
            // Show an edited device name in Control Center too (briefly toggles output).
            store.commitDriverNameFormat()
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

            Section {
                DriverNameFormatSection()
            } header: {
                Text("Device Name")
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

/// Edits the name macOS shows for Equaliser's virtual device in automatic mode.
private struct DriverNameFormatSection: View {
    @EnvironmentObject var store: EqualiserStore
    @StateObject private var field = DriverNameFormatFieldController()

    /// Inserts at the field's cursor, or appends if the field is unavailable.
    private func insert(_ segment: DriverNameFormat.Segment) {
        if !field.insert(segment) {
            store.driverNameFormat = DriverNameFormat(segments: store.driverNameFormat.segments + [segment])
        }
    }

    private var previewValues: DriverNameFormat.Values {
        let device = store.selectedOutputDeviceID.flatMap { uid in
            store.outputDevices.first { $0.uid == uid }?.name
        } ?? "Speakers"
        return DriverNameFormat.Values(
            device: device,
            preset: store.presetManager.selectedPresetName,
            eqEnabled: !store.isBypassed
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DriverNameFormatField(format: $store.driverNameFormat, controller: field)

            HStack(spacing: 6) {
                ForEach(DriverNameFormat.Token.allCases, id: \.self) { token in
                    Button(token.displayName) {
                        insert(.token(token))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Insert \(token.displayName) at the cursor")
                }
                Button("→") {
                    insert(.text(" → "))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Insert an arrow at the cursor")
                Spacer()
                Button("Reset") {
                    store.driverNameFormat = .default
                }
                .controlSize(.small)
                .disabled(store.driverNameFormat == .default)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview: \(store.driverNameFormat.render(previewValues))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Shown in macOS Sound settings in automatic mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.driverNameFormat.usesEQTokens {
                    Text("Preset and EQ State update in Control Center on the next output switch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

struct AboutTab: View {
    @EnvironmentObject var store: EqualiserStore
    @StateObject private var driverManager = DriverManager.shared
    @State private var showingUpToDate = false
    @State private var upToDateTask: Task<Void, Never>?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var driverVersion: String? {
        switch driverManager.status {
        case .installed(let version): version
        case .needsUpdate(let current, _): current
        default: nil
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("v\(appVersion) (\(buildVersion))")
                            .font(.headline)
                        if let version = driverVersion {
                            Text("Driver v\(version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 16) {
                    Spacer()
                    Link("Website", destination: URL(string: UPDATE_DOWNLOAD_URL)!)
                    Link("Documentation", destination: URL(string: DOCS_URL)!)
                    Link("GitHub", destination: URL(string: GITHUB_REPO_URL)!)
                    Spacer()
                }
                .font(.callout)
            } header: {
                Text("Equaliser")
            }

            Section {
                if store.updateService.updateAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                        if let version = store.updateService.latestVersion {
                            Text("v\(version) is available")
                                .font(.callout)
                        } else {
                            Text("Update available")
                                .font(.callout)
                        }
                        Spacer()
                        Button("Download") {
                            if let url = URL(string: UPDATE_DOWNLOAD_URL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if showingUpToDate {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("You're up to date")
                            .font(.callout)
                        Spacer()
                    }
                } else {
                    HStack {
                        Spacer()
                        if store.updateService.isChecking {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Check for Updates") {
                                showingUpToDate = false
                                upToDateTask?.cancel()
                                store.updateService.forceCheckForUpdates()
                            }
                            .disabled(store.updateService.isChecking)
                        }
                        Spacer()
                    }
                }
            } header: {
                Text("Updates")
            }

        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Text("© Christophe Knage")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .padding()
        .onChange(of: store.updateService.isChecking) { _, isChecking in
            guard !isChecking else { return }
            // Check just finished — show "up to date" if no update found
            if !store.updateService.updateAvailable {
                showingUpToDate = true
                upToDateTask?.cancel()
                upToDateTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    showingUpToDate = false
                }
            }
        }
    }
}

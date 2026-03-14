//  DriverInstallationView.swift
//  Equaliser
//
//  SwiftUI view for driver installation flow - shown when driver is required but not installed.

import SwiftUI

struct DriverInstallationView: View {
    @ObservedObject private var driverManager = DriverManager.shared
    @EnvironmentObject var store: EqualiserStore
    @Environment(\.dismiss) private var dismiss
    
    var onInstall: (() -> Void)?
    var onSwitchToManual: (() -> Void)?
    
    @State private var installError: String?
    
    var body: some View {
        VStack(spacing: 24) {
            headerView
            
            contentView
            
            if let error = installError {
                errorBanner(error)
            }
            
            buttonView
        }
        .padding(32)
        .frame(width: 480)
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var headerView: some View {
        Image(systemName: "speaker.wave.3.fill")
            .font(.system(size: 48))
            .foregroundStyle(Color.accentColor)
        
        Text("Audio Driver Required")
            .font(.title)
            .fontWeight(.semibold)
        
        Text("Automatic mode requires a virtual audio driver to route audio through the equaliser. Install the driver to continue.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        switch driverManager.status {
        case .notInstalled:
            notInstalledView
        case .installed(let version):
            installedView(version: version)
        case .needsUpdate(let current, let bundled):
            updateView(currentVersion: current, bundledVersion: bundled)
        case .error(let message):
            errorView(message: message)
        }
    }
    
    private var notInstalledView: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Driver not installed")
                    .fontWeight(.medium)
                Spacer()
            }
            
            Text("Click the button below to install the driver. You will be prompted for your administrator password.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func installedView(version: String) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Driver installed (v\(version))")
                    .fontWeight(.medium)
                Spacer()
            }
            
            Text("The virtual audio driver is installed. Audio routing will start automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func updateView(currentVersion: String, bundledVersion: String) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                Text("Update available")
                    .fontWeight(.medium)
                Spacer()
            }
            
            Text("Installed: v\(currentVersion) → Bundled: v\(bundledVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Text("Click the button below to update the driver to the latest version.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Error")
                    .fontWeight(.medium)
                Spacer()
            }
            
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
            Button {
                installError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Buttons
    
    @ViewBuilder
    private var buttonView: some View {
        HStack(spacing: 12) {
            Button("Switch to Manual Mode") {
                onSwitchToManual?()
                dismiss()
            }
            .buttonStyle(.bordered)
            .disabled(driverManager.isInstalling)
            .keyboardShortcut(.cancelAction)
            
            switch driverManager.status {
            case .notInstalled, .needsUpdate, .error:
                Button("Install Driver") {
                    installDriver()
                }
                .buttonStyle(.borderedProminent)
                .disabled(driverManager.isInstalling)
                .keyboardShortcut(.defaultAction)
                
            case .installed:
                Button("Continue") {
                    onInstall?()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        
        if driverManager.isInstalling {
            ProgressView()
                .scaleEffect(0.8)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Actions
    
    private func installDriver() {
        installError = nil
        
        Task {
            do {
                try await driverManager.installDriver()
                // Check if now installed
                if case .installed = driverManager.status {
                    onInstall?()
                    dismiss()
                }
            } catch {
                installError = error.localizedDescription
            }
        }
    }
}

#Preview("Not Installed") {
    DriverInstallationView()
        .environmentObject(EqualiserStore())
}
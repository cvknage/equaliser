//  DriverInstallationView.swift
//  Equaliser
//
//  SwiftUI view for driver installation flow - shown when driver is required but not installed.

import SwiftUI

struct DriverInstallationView: View {
    @StateObject private var driverManager = DriverManager.shared
    @Environment(\.dismiss) private var dismiss

    var onInstall: (() -> Void)?
    var onQuit: (() -> Void)?

    @State private var installError: String?
    
    var body: some View {
        VStack(spacing: 24) {
            headerView

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

        Text("Virtual Audio Driver Required")
            .font(.title)
            .fontWeight(.semibold)

        Text("Equaliser needs a virtual audio driver to process your system's audio. It only runs when Equaliser is active.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Error Banner

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
        switch driverManager.status {
        case .notInstalled, .needsUpdate, .error:
            HStack(spacing: 16) {
                Button("Quit") {
                    dismiss()
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("q", modifiers: .command)

                Button("Install Driver") {
                    installDriver()
                }
                .buttonStyle(.borderedProminent)
                .disabled(driverManager.isInstalling)
                .keyboardShortcut(.defaultAction)
            }

            if driverManager.isInstalling {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.top, 8)
            }

        case .installed(let version):
            Text("Driver installed (v\(version))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Continue") {
                onInstall?()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
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
                }
            } catch {
                installError = error.localizedDescription
            }
        }
    }
}

#Preview("Not Installed") {
    DriverInstallationView()
}

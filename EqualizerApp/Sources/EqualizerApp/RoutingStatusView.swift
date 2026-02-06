import SwiftUI

/// Displays the current audio routing status.
struct RoutingStatusView: View {
    let status: RoutingStatus

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusText
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusBackground)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .idle:
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .active:
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch status {
        case .idle:
            Text("Select devices to start")
                .foregroundStyle(.secondary)
        case .starting:
            Text("Starting...")
                .foregroundStyle(.secondary)
        case .active(let inputName, let outputName):
            Text("\(inputName) → \(outputName)")
                .fontWeight(.medium)
        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var statusBackground: Color {
        switch status {
        case .idle, .starting:
            return Color.clear
        case .active:
            return Color.green.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        }
    }
}

#Preview("Idle") {
    RoutingStatusView(status: .idle)
        .padding()
}

#Preview("Starting") {
    RoutingStatusView(status: .starting)
        .padding()
}

#Preview("Active") {
    RoutingStatusView(status: .active(inputName: "BlackHole 2ch", outputName: "Built-in Output"))
        .padding()
}

#Preview("Error") {
    RoutingStatusView(status: .error("Sample rate mismatch: 48000 Hz vs 44100 Hz"))
        .padding()
}

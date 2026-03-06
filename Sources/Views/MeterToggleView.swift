import SwiftUI

/// Toggle control for meters with help tooltip explaining CPU usage.
struct MeterToggleView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 8) {
            // Toggle with switch style like System EQ
            Toggle("Meters", isOn: store.metersEnabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Help icon to the right of toggle
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp, arrowEdge: .trailing) {
                Text("Level meters update at 30 FPS and can increase CPU usage. When this window is closed or minimized, meters stop rendering. Disable to reduce CPU while the window is open.")
                    .font(.caption)
                    .padding(12)
                    .frame(width: 250)
            }
        }
    }
}

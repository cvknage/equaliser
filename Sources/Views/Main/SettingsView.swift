import SwiftUI

/// App preferences accessible via Cmd+,
struct SettingsView: View {
    @EnvironmentObject var store: EqualiserStore

    var body: some View {
        Form {
            Section("Display") {
                Picker("Bandwidth Format", selection: $store.bandwidthDisplayMode) {
                    ForEach(BandwidthDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 100)
    }
}

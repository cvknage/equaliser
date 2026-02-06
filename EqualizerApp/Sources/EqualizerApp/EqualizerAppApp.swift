import AVFoundation
import SwiftUI

@main
struct EqualizerAppMain: App {
    @StateObject private var store = EqualizerStore()

    init() {
        // Hide dock icon permanently - this is a menu bar app
        // Defer until NSApp is available (it's nil during init)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }

        // Request microphone access for audio routing
        AVAudioApplication.requestRecordPermission { granted in
            if !granted {
                print("Microphone access denied. Audio routing will be unavailable.")
            }
        }
    }

    var body: some Scene {
        // Main EQ settings window (hidden by default, opened on demand)
        Window("Equalizer Settings", id: "eq-settings") {
            EQWindowView()
                .environmentObject(store)
        }
        .defaultPosition(.center)
        .defaultSize(width: 800, height: 500)

        // Menu bar popover (always available)
        MenuBarExtra("Equalizer", systemImage: "slider.horizontal.3") {
            MenuBarContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar popover content - quick access controls.
struct MenuBarContentView: View {
    @EnvironmentObject var store: EqualizerStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                Text("Equalizer")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)

            // Device Pickers
            DevicePickerView()

            // Routing Status
            RoutingStatusView(status: store.routingStatus)

            Divider()

            // Controls
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Bypass EQ", isOn: $store.isBypassed)
                    .toggleStyle(.checkbox)

                if store.routingStatus.isActive {
                    Button("Stop Routing") {
                        store.stopRouting()
                    }
                    .buttonStyle(.bordered)
                } else if case .error = store.routingStatus {
                    Button("Retry") {
                        store.reconfigureRouting()
                    }
                    .buttonStyle(.bordered)
                } else if store.routingStatus == .idle
                            && store.selectedInputDeviceID != nil
                            && store.selectedOutputDeviceID != nil {
                    Button("Start Routing") {
                        store.reconfigureRouting()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // EQ Settings Button
            Button("Open EQ Settings...") {
                openWindow(id: "eq-settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Spacer()

            // Footer
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280, height: 380)
    }
}

/// The main EQ settings window - detailed controls.
struct EQWindowView: View {
    @EnvironmentObject var store: EqualizerStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Equalizer")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("32-band parametric equalizer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Reset button
                Button("Flatten") {
                    for i in 0..<32 {
                        store.updateBandGain(index: i, gain: 0)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Routing status indicator
                if store.routingStatus.isActive {
                    Label("Active", systemImage: "waveform.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Inactive", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // 32-band EQ sliders
            EQBandGridView()

            Divider()

            // Footer with bypass toggle
            HStack {
                Toggle("Bypass EQ", isOn: $store.isBypassed)
                    .toggleStyle(.checkbox)

                Spacer()

                Button("Close") {
                    dismissWindow(id: "eq-settings")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 900, minHeight: 400)
    }
}

/// Grid of 32 EQ band sliders.
struct EQBandGridView: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<32, id: \.self) { index in
                    EQBandSliderView(
                        index: index,
                        frequency: store.eqConfiguration.bands[index].frequency,
                        gain: Binding(
                            get: { store.eqConfiguration.bands[index].gain },
                            set: { store.updateBandGain(index: index, gain: $0) }
                        )
                    )
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

/// A single vertical EQ band slider with frequency label.
struct EQBandSliderView: View {
    let index: Int
    let frequency: Float
    @Binding var gain: Float

    /// Gain range in dB.
    private let minGain: Float = -12
    private let maxGain: Float = 12

    var body: some View {
        VStack(spacing: 4) {
            // Gain value readout
            Text(gainString)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(gain == 0 ? .secondary : .primary)
                .frame(width: 32)

            // Vertical slider (custom)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 6)

                    // Zero line indicator
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 12, height: 1)
                        .offset(y: -geo.size.height / 2)

                    // Filled portion (from center)
                    let normalizedGain = CGFloat((gain - minGain) / (maxGain - minGain))
                    let centerY = geo.size.height / 2

                    if gain >= 0 {
                        // Positive gain: fill from center upward
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillColor)
                            .frame(width: 6, height: centerY * CGFloat(gain / maxGain))
                            .offset(y: -centerY + centerY * CGFloat(gain / maxGain) / 2)
                    } else {
                        // Negative gain: fill from center downward
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillColor)
                            .frame(width: 6, height: centerY * CGFloat(-gain / minGain))
                            .offset(y: -centerY / 2 + centerY * CGFloat(-gain / minGain) / 2)
                    }

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 1)
                        .frame(width: 14, height: 14)
                        .offset(y: -(normalizedGain * geo.size.height - 7))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = 1 - (value.location.y / geo.size.height)
                            let clamped = min(max(fraction, 0), 1)
                            gain = Float(clamped) * (maxGain - minGain) + minGain
                        }
                )
                .onTapGesture(count: 2) {
                    // Double-tap to reset to 0 dB
                    gain = 0
                }
            }
            .frame(width: 24, height: 180)

            // Frequency label
            Text(frequencyString)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32)
        }
        .padding(.vertical, 4)
    }

    private var gainString: String {
        if gain >= 0 {
            return String(format: "+%.0f", gain)
        } else {
            return String(format: "%.0f", gain)
        }
    }

    private var frequencyString: String {
        if frequency >= 1000 {
            return String(format: "%.0fk", frequency / 1000)
        } else {
            return String(format: "%.0f", frequency)
        }
    }

    private var fillColor: Color {
        if abs(gain) < 1 {
            return .gray
        } else if gain > 0 {
            return .green
        } else {
            return .orange
        }
    }
}

#Preview("Menu Bar") {
    MenuBarContentView()
        .environmentObject(EqualizerStore())
}

#Preview("EQ Window") {
    EQWindowView()
        .environmentObject(EqualizerStore())
}

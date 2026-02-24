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
        .defaultSize(width: 700, height: 520)

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
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                Text("Equalizer")
                    .font(.headline)
                Spacer()
            }

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 4)

            // Device Pickers
            DevicePickerView(layout: .vertical)

            Divider()
                .padding(.vertical, 4)

            // Controls
            Toggle("Bypass EQ", isOn: $store.isBypassed)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 4)

            // EQ Settings Button
            Button("Open EQ Settings...") {
                openWindow(id: "eq-settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

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
        .padding(12)
        .frame(width: 240, height: 300)
    }

    private var statusColor: Color {
        switch store.routingStatus {
        case .idle:
            return .gray
        case .starting:
            return .orange
        case .active:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch store.routingStatus {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting..."
        case .active:
            return "Active"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

/// The main EQ settings window - detailed controls.
struct EQWindowView: View {
    @EnvironmentObject var store: EqualizerStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 12) {
            // Header: App title + devices + routing controls
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Equalizer")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Parametric EQ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Device pickers
                DevicePickerView(layout: .horizontal)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Routing status + controls
            HStack(alignment: .center, spacing: 16) {
                RoutingStatusView(status: store.routingStatus)
                    .frame(maxWidth: 280, alignment: .leading)

                LevelMetersView(
                    inputState: store.inputMeterLevel,
                    outputState: store.outputMeterLevel,
                    inputGain: $store.inputGain,
                    outputGain: $store.outputGain,
                    isActive: store.routingStatus.isActive
                )
                .frame(width: 300)

                Spacer()

                // Routing action buttons
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
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Band controls toolbar
            HStack {
                Text("Bands")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                BandCountControl()

                Spacer()

                Button("Flatten") {
                    for i in 0..<store.bandCount {
                        store.updateBandGain(index: i, gain: 0)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // EQ sliders
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
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct LevelMetersView: View {
    let inputState: StereoMeterState
    let outputState: StereoMeterState
    @Binding var inputGain: Float
    @Binding var outputGain: Float
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            StereoMeterGroup(title: "Input", state: inputState, gain: $inputGain, isActive: isActive)
            StereoMeterGroup(title: "Output", state: outputState, gain: $outputGain, isActive: isActive)
        }
    }
}

struct StereoMeterGroup: View {
    let title: String
    let state: StereoMeterState
    @Binding var gain: Float
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 12) {
                DualPeakMeterView(channelLabel: "L", state: state.left, isActive: isActive)
                DualPeakMeterView(channelLabel: "R", state: state.right, isActive: isActive)
                GainStepperControl(gain: $gain, isActive: isActive)
            }

        }
    }
}

struct DualPeakMeterView: View {
    let channelLabel: String
    let state: ChannelMeterState
    let isActive: Bool

    private let gradientStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.0, green: 0.45, blue: 0.95), location: 0.0),
        .init(color: .green, location: 0.4),
        .init(color: .yellow, location: 0.7),
        .init(color: .orange, location: 0.9),
        .init(color: .red, location: 1.0)
    ]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.18))
                        )

                    if state.peak > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(fillColor(for: state))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(
                                Rectangle()
                                    .frame(width: proxy.size.width, height: proxy.size.height * CGFloat(state.peak))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            )
                            .animation(.easeOut(duration: 0.08), value: state.peak)
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: -proxy.size.height * CGFloat(state.peakHold))

                    if state.isClipping {
                        ClipIndicator()
                            .frame(height: 10)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 2)
                    }
                }
                .opacity(isActive ? 1 : 0.35)
            }
            .frame(width: 24, height: 84)

            Text(channelLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func fillColor(for state: ChannelMeterState) -> LinearGradient {
        if state.isClipping {
            return LinearGradient(colors: [.red, .red], startPoint: .bottom, endPoint: .top)
        }
        return LinearGradient(
            gradient: Gradient(stops: gradientStops),
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

struct ClipIndicator: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .overlay(
                Text("CLIP")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

struct GainStepperControl: View {
    @Binding var gain: Float
    let isActive: Bool

    @FocusState private var isFocused: Bool
    @State private var editedValue: String = ""

    var body: some View {
        VStack(spacing: 6) {
            StepperButton(symbol: "+", action: { adjustGain(by: 0.5) })
                .disabled(!isActive)

            TextField("0.0", text: Binding(
                get: { editedValue.isEmpty ? Self.format(gain) : editedValue },
                set: { editedValue = $0 }
            ))
            .frame(width: 60)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .focused($isFocused)
            .disabled(!isActive)
            .onSubmit(applyEditedValue)
            .onTapGesture(count: 2) {
                gain = 0
            }

            StepperButton(symbol: "-", action: { adjustGain(by: -0.5) })
                .disabled(!isActive)
        }
        .opacity(isActive ? 1 : 0.35)
        .onAppear {
            editedValue = Self.format(gain)
        }
        .onChange(of: gain) { _, newValue in
            if !isFocused {
                editedValue = Self.format(newValue)
            }
        }
        .onChange(of: editedValue) { _, newValue in
            guard isFocused else { return }
            let allowed = CharacterSet(charactersIn: "-0123456789.")
            let filteredScalars = newValue.unicodeScalars.filter { allowed.contains($0) }
            let filtered = String(filteredScalars)
            if filtered != newValue {
                editedValue = filtered
            }
        }
    }

    private func adjustGain(by delta: Float) {
        let newValue = EqualizerStore.clampGain(gain + delta)
        gain = Self.roundToStep(newValue)
        editedValue = Self.format(gain)
    }

    private func applyEditedValue() {
        guard let value = Float(editedValue) else {
            editedValue = Self.format(gain)
            isFocused = false
            return
        }
        gain = Self.roundToStep(EqualizerStore.clampGain(value))
        editedValue = Self.format(gain)
        isFocused = false
    }

    private static func roundToStep(_ value: Float) -> Float {
        (value * 2).rounded() / 2
    }

    private static func format(_ value: Float) -> String {
        String(format: "%+.1f", value)
    }
}

/// Grid of EQ band sliders.
struct EQBandGridView: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(0..<store.bandCount, id: \.self) { index in
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
                .frame(minWidth: max(0, proxy.size.width - 24), maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
            }
        }
    }
}

struct BandCountControl: View {
    @EnvironmentObject var store: EqualizerStore
    @FocusState private var isFocused: Bool
    @State private var editedValue: String = ""

    var body: some View {
        HStack(spacing: 8) {
            StepperButton(symbol: "-", action: { adjustBands(by: -1) })
            TextField("Bands", text: Binding(
                get: { editedValue.isEmpty ? "\(store.bandCount)" : editedValue },
                set: { editedValue = $0 }
            ))
            .frame(width: 60)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .focused($isFocused)
            .onSubmit(applyEditedValue)
            StepperButton(symbol: "+", action: { adjustBands(by: 1) })
        }
        .onAppear {
            editedValue = "\(store.bandCount)"
        }
        .onChange(of: store.bandCount) { _, newValue in
            if !isFocused {
                editedValue = "\(newValue)"
            }
        }
        .onChange(of: editedValue) { _, newValue in
            if !newValue.isEmpty {
                let digitsOnly = newValue.filter { $0.isNumber }
                if digitsOnly != newValue {
                    editedValue = digitsOnly
                }
            }
        }
    }

    private func adjustBands(by delta: Int) {
        let newCount = store.bandCount + delta
        applyBandCount(newCount)
    }

    private func applyEditedValue() {
        guard let value = Int(editedValue) else {
            editedValue = "\(store.bandCount)"
            return
        }
        applyBandCount(value)
        isFocused = false
    }

    private func applyBandCount(_ count: Int) {
        let clamped = EQConfiguration.clampBandCount(count)
        store.bandCount = clamped
        editedValue = "\(clamped)"
    }
}

private struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol == "+" ? "plus" : "minus")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
                let height = geo.size.height
                let halfHeight = height / 2
                let positiveRatio = min(max(gain / maxGain, 0), 1)
                let negativeRatio = min(max(abs(gain) / abs(minGain), 0), 1)
                let positiveHeight = CGFloat(positiveRatio) * halfHeight
                let negativeHeight = gain < 0 ? CGFloat(negativeRatio) * halfHeight : 0
                let normalizedGain = CGFloat((gain - minGain) / (maxGain - minGain))
                let thumbOffset = (0.5 - normalizedGain) * height

                ZStack {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 6, height: height)

                    // Zero line indicator
                    Rectangle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 12, height: 1)

                    // Positive fill (extends upward from zero)
                    if gain > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillColor)
                            .frame(width: 6, height: positiveHeight)
                            .offset(y: -positiveHeight / 2)
                            .animation(.easeOut(duration: 0.08), value: gain)
                    }

                    // Negative fill (extends downward from zero)
                    if gain < 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillColor)
                            .frame(width: 6, height: negativeHeight)
                            .offset(y: negativeHeight / 2)
                            .animation(.easeOut(duration: 0.08), value: gain)
                    }

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 1)
                        .frame(width: 14, height: 14)
                        .offset(y: thumbOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

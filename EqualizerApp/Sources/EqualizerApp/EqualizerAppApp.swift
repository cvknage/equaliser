import AVFoundation
import SwiftUI

private extension AVAudioUnitEQFilterType {
    var displayName: String {
        switch self {
        case .parametric:
            return "Parametric"
        case .lowPass:
            return "Low Pass"
        case .highPass:
            return "High Pass"
        case .lowShelf:
            return "Low Shelf"
        case .highShelf:
            return "High Shelf"
        case .bandPass:
            return "Band Pass"
        case .bandStop:
            return "Notch"
        case .resonantLowPass:
            return "Resonant Low Pass"
        case .resonantHighPass:
            return "Resonant High Pass"
        case .resonantLowShelf:
            return "Resonant Low Shelf"
        case .resonantHighShelf:
            return "Resonant High Shelf"
        @unknown default:
            return "Unknown"
        }
    }

    var abbreviation: String {
        switch self {
        case .parametric:
            return "Bell"
        case .lowPass:
            return "LP"
        case .highPass:
            return "HP"
        case .lowShelf:
            return "LS"
        case .highShelf:
            return "HS"
        case .bandPass:
            return "BP"
        case .bandStop:
            return "Notch"
        case .resonantLowPass:
            return "RLP"
        case .resonantHighPass:
            return "RHP"
        case .resonantLowShelf:
            return "RLS"
        case .resonantHighShelf:
            return "RHS"
        @unknown default:
            return "?"
        }
    }

    static var allCasesInUIOrder: [AVAudioUnitEQFilterType] {
        [.parametric, .lowPass, .highPass, .lowShelf, .highShelf,
         .bandPass, .bandStop, .resonantLowPass, .resonantHighPass,
         .resonantLowShelf, .resonantHighShelf]
    }
}

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
                    inputRMSState: store.inputMeterRMS,
                    outputRMSState: store.outputMeterRMS,
                    inputGain: $store.inputGain,
                    outputGain: $store.outputGain,
                    isActive: store.routingStatus.isActive
                )
                .frame(width: 620)

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
    let inputRMSState: StereoMeterState
    let outputRMSState: StereoMeterState
    @Binding var inputGain: Float
    @Binding var outputGain: Float
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Peak meters with scales on left
            StereoMeterGroup(title: "Peak In", state: inputState, gain: $inputGain, isActive: isActive, showScale: true)
            StereoMeterGroup(title: "Peak Out", state: outputState, gain: $outputGain, isActive: isActive, showScale: true)

            // RMS meters with scales on left
            StereoMeterGroupRMS(title: "RMS In", rmsState: inputRMSState, gain: $inputGain, isActive: isActive, showScale: true)
            StereoMeterGroupRMS(title: "RMS Out", rmsState: outputRMSState, gain: $outputGain, isActive: isActive, showScale: true)
        }
    }
}

struct StereoMeterGroup: View {
    let title: String
    let state: StereoMeterState
    @Binding var gain: Float
    let isActive: Bool
    var showScale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 4) {
                if showScale {
                    MeterScaleView(height: MeterConstants.meterHeight)
                }
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
                            .animation(.easeOut(duration: 0.03), value: state.peak)
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
            .frame(width: 18, height: 126)

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

struct DualPeakRMSMeterView: View {
    let channelLabel: String
    let rmsState: ChannelMeterState
    let isActive: Bool

    private let rmsGradientStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.0, green: 0.35, blue: 0.4), location: 0.0),
        .init(color: Color(red: 0.0, green: 0.5, blue: 0.5), location: 0.4),
        .init(color: Color(red: 0.5, green: 0.6, blue: 0.2), location: 0.7),
        .init(color: Color(red: 0.7, green: 0.5, blue: 0.2), location: 0.9),
        .init(color: Color(red: 0.6, green: 0.2, blue: 0.2), location: 1.0)
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

                    if rmsState.rms > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(
                                gradient: Gradient(stops: rmsGradientStops),
                                startPoint: .bottom,
                                endPoint: .top
                            ))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(
                                Rectangle()
                                    .frame(width: proxy.size.width, height: proxy.size.height * CGFloat(rmsState.rms))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            )
                            .animation(.easeOut(duration: 0.03), value: rmsState.rms)
                    }
                }
                .opacity(isActive ? 1 : 0.35)
            }
            .frame(width: 14, height: 126)

            Text(channelLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct StereoMeterGroupRMS: View {
    let title: String
    let rmsState: StereoMeterState
    @Binding var gain: Float
    let isActive: Bool
    var showScale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 4) {
                if showScale {
                    MeterScaleView(height: MeterConstants.meterHeight)
                }
                DualPeakRMSMeterView(channelLabel: "L", rmsState: rmsState.left, isActive: isActive)
                DualPeakRMSMeterView(channelLabel: "R", rmsState: rmsState.right, isActive: isActive)
                GainStepperControl(gain: $gain, isActive: isActive)
            }

        }
    }
}

struct MeterScaleView: View {
    let height: CGFloat

    var body: some View {
        // Match DualPeakMeterView structure: VStack(spacing: 4) with content + label
        VStack(spacing: 4) {
            Canvas { context, size in
                for db in MeterConstants.standardTickValues {
                    let position = MeterConstants.normalizedPosition(for: db)
                    let y = size.height * (1 - CGFloat(position))

                    // Draw tick mark
                    let tickWidth: CGFloat = db == 0 ? 6 : 4
                    let tickRect = CGRect(
                        x: size.width - tickWidth,
                        y: y - 0.5,
                        width: tickWidth,
                        height: 1
                    )
                    context.fill(Path(tickRect), with: .color(.gray.opacity(0.6)))

                    // Draw label with appropriate anchor to avoid clipping
                    let label = db == 0 ? "0" : String(format: "%.0f", db)
                    let text = Text(label)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Use different anchors for top/bottom to keep text in bounds
                    let anchor: UnitPoint
                    if db == 0 {
                        anchor = .topTrailing  // Top label: text below tick
                    } else if db == -36 {
                        anchor = .bottomTrailing  // Bottom label: text above tick
                    } else {
                        anchor = .trailing  // Middle labels: centered on tick
                    }

                    context.draw(
                        context.resolve(text),
                        at: CGPoint(x: size.width - tickWidth - 3, y: y),
                        anchor: anchor
                    )
                }
            }
            .frame(width: 32, height: height)

            // Match channel label height from DualPeakMeterView
            Text(" ")
                .font(.caption2)
                .foregroundStyle(.clear)
        }
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
                HStack(spacing: 6) {
                    ForEach(0..<store.bandCount, id: \.self) { index in
                        EQBandSliderView(
                            index: index,
                            band: store.eqConfiguration.bands[index],
                            gain: Binding(
                                get: { store.eqConfiguration.bands[index].gain },
                                set: { store.updateBandGain(index: index, gain: $0) }
                            ),
                            frequencyUpdate: { value in
                                let clamped = min(max(value, 20), 20_000)
                                store.updateBandFrequency(index: index, frequency: clamped)
                            },
                            bandwidthUpdate: { value in
                                let clamped = min(max(value, 0.05), 5)
                                store.updateBandBandwidth(index: index, bandwidth: clamped)
                            },
                            filterTypeUpdate: { store.updateBandFilterType(index: index, filterType: $0) },
                            bypassUpdate: { store.updateBandBypass(index: index, bypass: $0) }
                        )
                        .frame(width: 72)
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

/// Inline, tap-to-edit numeric value used for frequency/bandwidth fields.
private struct InlineEditableValue: View {
    let value: Float
    let displayFormatter: (Float) -> String
    let inputFormatter: (Float) -> String
    let width: CGFloat
    let alignment: Alignment
    let onCommit: (Float) -> Void

    @State private var isEditing = false
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: width)
                    .focused($isFocused)
                    .onAppear {
                        text = inputFormatter(value)
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                    }
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
            } else {
                Text(displayFormatter(value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: width, alignment: alignment)
                    .onTapGesture {
                        text = inputFormatter(value)
                        isEditing = true
                    }
            }
        }
    }

    private func commit() {
        guard isEditing else { return }
        defer { isEditing = false }
        if let newValue = Float(text) {
            onCommit(newValue)
        }
    }
}

private struct EQBandDetailPopover: View {
    let filterTypeUpdate: (AVAudioUnitEQFilterType) -> Void
    let bypassUpdate: (Bool) -> Void

    @State private var filterType: AVAudioUnitEQFilterType
    @State private var bypass: Bool

    init(band: EQBandConfiguration,
         filterTypeUpdate: @escaping (AVAudioUnitEQFilterType) -> Void,
         bypassUpdate: @escaping (Bool) -> Void) {
        _filterType = State(initialValue: band.filterType)
        _bypass = State(initialValue: band.bypass)
        self.filterTypeUpdate = filterTypeUpdate
        self.bypassUpdate = bypassUpdate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Band Options")
                .font(.headline)

            Picker("Filter Type", selection: $filterType) {
                ForEach(AVAudioUnitEQFilterType.allCasesInUIOrder, id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: filterType) { _, newValue in
                filterTypeUpdate(newValue)
            }

            Toggle("Bypass Band", isOn: $bypass)
                .onChange(of: bypass) { _, newValue in
                    bypassUpdate(newValue)
                }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// A fully parametric EQ band column.
struct EQBandSliderView: View {
    let index: Int
    let band: EQBandConfiguration
    @Binding var gain: Float
    let frequencyUpdate: (Float) -> Void
    let bandwidthUpdate: (Float) -> Void
    let filterTypeUpdate: (AVAudioUnitEQFilterType) -> Void
    let bypassUpdate: (Bool) -> Void

    /// Gain range in dB.
    private let minGain: Float = -12
    private let maxGain: Float = 12

    @State private var isShowingDetail = false

    var body: some View {
        VStack(spacing: 8) {
            header
            bandwidthEditor
            slider
                .frame(height: 175)
            Text(gainString)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(gain == 0 ? .secondary : .primary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
        .opacity(band.bypass ? 0.35 : 1)
        .frame(width: 68)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    isShowingDetail = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingDetail, arrowEdge: .top) {
                    EQBandDetailPopover(
                        band: band,
                        filterTypeUpdate: filterTypeUpdate,
                        bypassUpdate: bypassUpdate
                    )
                    .frame(width: 220)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(band.filterType.abbreviation)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                InlineEditableValue(
                    value: band.frequency,
                    displayFormatter: { String(format: "%.0f Hz", $0) },
                    inputFormatter: { String(format: "%.0f", $0) },
                    width: 56,
                    alignment: .leading,
                    onCommit: frequencyUpdate
                )
            }
        }
    }

    private var bandwidthEditor: some View {
        InlineEditableValue(
            value: band.bandwidth,
            displayFormatter: { String(format: "BW: %.2f", $0) },
            inputFormatter: { String(format: "%.2f", $0) },
            width: 70,
            alignment: .leading,
            onCommit: bandwidthUpdate
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var slider: some View {
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
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 8, height: height)

                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 14, height: 1)

                if gain > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: 8, height: positiveHeight)
                        .offset(y: -positiveHeight / 2)
                        .animation(.easeOut(duration: 0.08), value: gain)
                }

                if gain < 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: 8, height: negativeHeight)
                        .offset(y: negativeHeight / 2)
                        .animation(.easeOut(duration: 0.08), value: gain)
                }

                Circle()
                    .fill(Color.white)
                    .shadow(radius: 1)
                    .frame(width: 16, height: 16)
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
                gain = 0
            }
        }
    }

    private var gainString: String {
        if gain >= 0 {
            return String(format: "+%.1f dB", gain)
        } else {
            return String(format: "%.1f dB", gain)
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

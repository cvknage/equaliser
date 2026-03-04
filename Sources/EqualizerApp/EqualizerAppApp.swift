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
        .defaultSize(width: 1060, height: 630)
        .windowResizability(.contentMinSize)

        // Menu bar popover (always available)
        MenuBarExtra("Equalizer", systemImage: "slider.horizontal.3") {
            MenuBarContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environmentObject(store)
        }
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

            // Preset Picker
            CompactPresetPicker()

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
        .frame(width: 240, height: 340)
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

    var body: some View {
        VStack(spacing: 12) {
            // Header: App title only
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
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Level meters + unified control panel
            HStack(alignment: .top, spacing: 16) {
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
                .layoutPriority(1)

                Spacer()

                // Unified control panel - device pickers, status, and buttons grouped together
                VStack(alignment: .trailing, spacing: 8) {
                    // Device pickers
                    DevicePickerView(layout: .horizontal)

                    RoutingStatusView(status: store.routingStatus)
                        .frame(width: 376)

                    // Routing action buttons
                    HStack(spacing: 8) {
                        if store.isBypassed {
                            Button("Activate EQ") {
                                store.isBypassed.toggle()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Bypass EQ") {
                                store.isBypassed.toggle()
                            }
                            .buttonStyle(.bordered)
                        }

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
                }
                .frame(minWidth: 376)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Preset and band controls toolbar
            HStack {
                PresetToolbar()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Bands")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                BandCountControl()

                Button("Flatten") {
                    for i in 0..<store.bandCount {
                        store.updateBandGain(index: i, gain: 0)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // EQ sliders
            EQBandGridView()
        }
        .frame(minWidth: 1060, minHeight: 570)
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
    @State private var isEditing = false
    @State private var editedValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            StepperButton(symbol: "-", action: { adjustBands(by: -1) })

            // Tap-to-edit band count display
            if isEditing {
                TextField("", text: $editedValue)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                    }
                    .onSubmit(commit)
                    .onChange(of: editedValue) { _, newValue in
                        let digitsOnly = newValue.filter { $0.isNumber }
                        if digitsOnly != newValue {
                            editedValue = digitsOnly
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
            } else {
                Text("\(store.bandCount)")
                    .frame(width: 60)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editedValue = "\(store.bandCount)"
                        isEditing = true
                    }
            }

            StepperButton(symbol: "+", action: { adjustBands(by: 1) })
        }
        .onChange(of: store.bandCount) { _, newValue in
            // Always update display when value changes externally (e.g., preset load)
            editedValue = "\(newValue)"
            isEditing = false  // Exit edit mode when value changes externally
        }
    }

    private func adjustBands(by delta: Int) {
        let newCount = store.bandCount + delta
        applyBandCount(newCount)
    }

    private func commit() {
        guard isEditing else { return }
        defer { isEditing = false }
        if let value = Int(editedValue) {
            applyBandCount(value)
        } else {
            editedValue = "\(store.bandCount)"
        }
    }

    private func applyBandCount(_ count: Int) {
        let clamped = EQConfiguration.clampBandCount(count)
        store.bandCount = clamped
        editedValue = "\(clamped)"
    }
}

private struct EQBandDetailPopover: View {
    @EnvironmentObject var store: EqualizerStore

    let gainUpdate: (Float) -> Void
    let frequencyUpdate: (Float) -> Void
    let bandwidthUpdate: (Float) -> Void
    let filterTypeUpdate: (AVAudioUnitEQFilterType) -> Void
    let bypassUpdate: (Bool) -> Void

    @State private var gain: Float
    @State private var frequency: Float
    @State private var bandwidth: Float
    @State private var filterType: AVAudioUnitEQFilterType
    @State private var bypass: Bool

    @State private var gainText: String = ""
    @State private var frequencyText: String = ""
    @State private var bandwidthText: String = ""

    init(band: EQBandConfiguration,
         gainUpdate: @escaping (Float) -> Void,
         frequencyUpdate: @escaping (Float) -> Void,
         bandwidthUpdate: @escaping (Float) -> Void,
         filterTypeUpdate: @escaping (AVAudioUnitEQFilterType) -> Void,
         bypassUpdate: @escaping (Bool) -> Void) {
        _gain = State(initialValue: band.gain)
        _frequency = State(initialValue: band.frequency)
        _bandwidth = State(initialValue: band.bandwidth)
        _filterType = State(initialValue: band.filterType)
        _bypass = State(initialValue: band.bypass)
        _gainText = State(initialValue: String(format: "%.1f", band.gain))
        _frequencyText = State(initialValue: String(format: "%.0f", band.frequency))
        // Bandwidth text is initialized in onAppear based on display mode
        _bandwidthText = State(initialValue: "")
        self.gainUpdate = gainUpdate
        self.frequencyUpdate = frequencyUpdate
        self.bandwidthUpdate = bandwidthUpdate
        self.filterTypeUpdate = filterTypeUpdate
        self.bypassUpdate = bypassUpdate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Band Options")
                .font(.headline)

            // Gain
            HStack {
                Text("Gain (dB)")
                Spacer()
                TextField("0.0", text: $gainText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        if let value = Float(gainText) {
                            let clamped = min(max(value, -12), 12)
                            gain = clamped
                            gainText = String(format: "%.1f", clamped)
                            gainUpdate(clamped)
                        }
                    }
            }

            // Frequency
            HStack {
                Text("Frequency (Hz)")
                Spacer()
                TextField("1000", text: $frequencyText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        if let value = Float(frequencyText) {
                            let clamped = min(max(value, 20), 20000)
                            frequency = clamped
                            frequencyText = String(format: "%.0f", clamped)
                            frequencyUpdate(clamped)
                        }
                    }
            }

            // Bandwidth / Q Factor
            HStack {
                Text(bandwidthLabel)
                Spacer()
                TextField("1.0", text: $bandwidthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        if let newBandwidth = BandwidthConverter.parseInput(bandwidthText, mode: store.bandwidthDisplayMode) {
                            let clamped = BandwidthConverter.clampBandwidth(newBandwidth)
                            bandwidth = clamped
                            bandwidthText = BandwidthConverter.formatForInput(bandwidth: clamped, mode: store.bandwidthDisplayMode)
                            bandwidthUpdate(clamped)
                        }
                    }
            }
            .onAppear {
                bandwidthText = BandwidthConverter.formatForInput(bandwidth: bandwidth, mode: store.bandwidthDisplayMode)
            }
            .onChange(of: store.bandwidthDisplayMode) { _, newMode in
                bandwidthText = BandwidthConverter.formatForInput(bandwidth: bandwidth, mode: newMode)
            }

            Divider()

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

    private var bandwidthLabel: String {
        switch store.bandwidthDisplayMode {
        case .octaves:
            return "Bandwidth (oct)"
        case .qFactor:
            return "Q Factor"
        }
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
            slider
                .frame(height: 175)
            InlineEditableValue(
                value: gain,
                displayFormatter: { $0 >= 0 ? String(format: "+%.1f", $0) : String(format: "%.1f", $0) },
                inputFormatter: { String(format: "%.1f", $0) },
                width: 56,
                alignment: .center,
                onCommit: { newGain in
                    gain = min(max(newGain, minGain), maxGain)
                }
            )
            .font(.system(size: 10, weight: .bold, design: .monospaced))
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
        VStack(alignment: .center, spacing: 4) {
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
                    gainUpdate: { newGain in
                        gain = min(max(newGain, minGain), maxGain)
                    },
                    frequencyUpdate: frequencyUpdate,
                    bandwidthUpdate: bandwidthUpdate,
                    filterTypeUpdate: filterTypeUpdate,
                    bypassUpdate: bypassUpdate
                )
                .frame(width: 240)
            }

            InlineEditableValue(
                value: band.frequency,
                displayFormatter: { String(format: "%.0f Hz", $0) },
                inputFormatter: { String(format: "%.0f", $0) },
                width: 56,
                alignment: .center,
                onCommit: frequencyUpdate
            )
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

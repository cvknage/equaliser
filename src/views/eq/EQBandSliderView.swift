import SwiftUI

/// A fully parametric EQ band column.
struct EQBandSliderView: View {
    let index: Int
    let band: EQBandConfiguration
    @Binding var gain: Float
    let frequencyUpdate: (Float) -> Void
    let qUpdate: (Float) -> Void
    let filterTypeUpdate: (FilterType) -> Void
    let bypassUpdate: (Bool) -> Void
    var onNavigateLeft: (() -> Void)? = nil
    var onNavigateRight: (() -> Void)? = nil
    var startEditing: Bool = false

    @State private var isShowingDetail = false
    @State private var dragStartGain: Float? = nil

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
                    gain = AudioConstants.clampGain(newGain)
                },
                onNavigateLeft: onNavigateLeft,
                onNavigateRight: onNavigateRight,
                startEditing: startEditing
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
                        gain = AudioConstants.clampGain(newGain)
                    },
                    frequencyUpdate: frequencyUpdate,
                    qUpdate: qUpdate,
                    filterTypeUpdate: filterTypeUpdate,
                    bypassUpdate: bypassUpdate,
                    onClose: { isShowingDetail = false }
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

    private var slider: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let normalizedGain = CGFloat((gain - AudioConstants.minGain) / (AudioConstants.maxGain - AudioConstants.minGain))
            let thumbOffset = (0.5 - normalizedGain) * height

            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 8, height: height)

                Rectangle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 12, height: 1)
                    .offset(x: -15)

                // Tick marks every 6 dB from -30 to +30 (excluding 0 and edges)
                ForEach([-30, -24, -18, -12, -6, 6, 12, 18, 24, 30], id: \.self) { db in
                    Rectangle()
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: 10, height: 1)
                        .offset(x: -15, y: (0.5 - CGFloat((Float(db) - AudioConstants.minGain) / (AudioConstants.maxGain - AudioConstants.minGain))) * height)
                }

                // Single fill from bottom to thumb (always green, gray when near zero)
                let fillHeight = CGFloat((gain - AudioConstants.minGain) / (AudioConstants.maxGain - AudioConstants.minGain)) * height
                let fillOffset = height - fillHeight / 2

                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(width: 8, height: fillHeight)
                    .offset(y: fillOffset - height / 2)
                    .animation(.easeOut(duration: 0.08), value: gain)

                Circle()
                    .fill(Color.white)
                    .shadow(radius: 1)
                    .frame(width: 16, height: 16)
                    .offset(y: thumbOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartGain == nil {
                                    dragStartGain = gain
                                }
                                let translation = value.translation.height
                                let gainRange = AudioConstants.maxGain - AudioConstants.minGain
                                let gainDelta = Float(-translation / height * CGFloat(gainRange))
                                let newGain = (dragStartGain ?? 0) + gainDelta
                                gain = AudioConstants.clampGain(newGain)
                            }
                            .onEnded { _ in
                                dragStartGain = nil
                            }
                    )
                    .onTapGesture(count: 2) {
                        gain = 0
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fillColor: Color {
        .blue
    }
}

struct EQBandDetailPopover: View {
    @EnvironmentObject var store: EqualiserStore

    let gainUpdate: (Float) -> Void
    let frequencyUpdate: (Float) -> Void
    let qUpdate: (Float) -> Void
    let filterTypeUpdate: (FilterType) -> Void
    let bypassUpdate: (Bool) -> Void
    let onClose: () -> Void

    @State private var gain: Float
    @State private var frequency: Float
    @State private var q: Float
    @State private var filterType: FilterType
    @State private var bypass: Bool

    @State private var gainText: String = ""
    @State private var frequencyText: String = ""
    @State private var bandwidthText: String = ""
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case gain, frequency, bandwidth
    }

    init(band: EQBandConfiguration,
         gainUpdate: @escaping (Float) -> Void,
         frequencyUpdate: @escaping (Float) -> Void,
         qUpdate: @escaping (Float) -> Void,
         filterTypeUpdate: @escaping (FilterType) -> Void,
         bypassUpdate: @escaping (Bool) -> Void,
         onClose: @escaping () -> Void) {
        _gain = State(initialValue: band.gain)
        _frequency = State(initialValue: band.frequency)
        _q = State(initialValue: band.q)
        _filterType = State(initialValue: band.filterType)
        _bypass = State(initialValue: band.bypass)
        _gainText = State(initialValue: String(format: "%.1f", band.gain))
        _frequencyText = State(initialValue: String(format: "%.0f", band.frequency))
        // Bandwidth text is initialized in onAppear based on display mode
        _bandwidthText = State(initialValue: "")
        self.gainUpdate = gainUpdate
        self.frequencyUpdate = frequencyUpdate
        self.qUpdate = qUpdate
        self.filterTypeUpdate = filterTypeUpdate
        self.bypassUpdate = bypassUpdate
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Band Options")
                .font(.caption)

            // Gain
            HStack {
                Text("Gain (dB)")
                Spacer()
                TextField("0.0", text: $gainText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .gain)
                    .onSubmit {
                        if let value = Float(gainText) {
                            let clamped = AudioConstants.clampGain(value)
                            gain = clamped
                            gainText = String(format: "%.1f", clamped)
                            gainUpdate(clamped)
                        }
                        focusedField = .frequency
                    }
                    .onKeyPress(.upArrow) {
                        adjustGain(by: 0.1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustGain(by: -0.1)
                        return .handled
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
                    .focused($focusedField, equals: .frequency)
                    .onSubmit {
                        if let value = Float(frequencyText) {
                            let clamped = AudioConstants.clampFrequency(value)
                            frequency = clamped
                            frequencyText = String(format: "%.0f", clamped)
                            frequencyUpdate(clamped)
                        }
                        focusedField = .bandwidth
                    }
                    .onKeyPress(.upArrow) {
                        adjustFrequency(by: 10)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustFrequency(by: -10)
                        return .handled
                    }
            }

            // Bandwidth / Q Factor
            // UI displays bandwidth or Q based on user preference, but model stores Q.
            // Conversion happens at the boundary.
            HStack {
                Text(bandwidthLabel)
                Spacer()
                TextField("1.0", text: $bandwidthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .bandwidth)
                    .onSubmit {
                        // parseInput returns the raw value in the mode's unit:
                        // .octaves → bandwidth in octaves, .qFactor → Q factor
                        if let inputValue = BandwidthConverter.parseInput(bandwidthText, mode: store.bandwidthDisplayMode) {
                            let qValue: Float
                            switch store.bandwidthDisplayMode {
                            case .octaves:
                                let clampedBandwidth = BandwidthConverter.clampBandwidth(inputValue)
                                qValue = BandwidthConverter.bandwidthToQ(clampedBandwidth)
                            case .qFactor:
                                qValue = BandwidthConverter.clampQ(inputValue)
                            }
                            q = qValue
                            bandwidthText = BandwidthConverter.formatForInput(q: qValue, mode: store.bandwidthDisplayMode)
                            qUpdate(qValue)
                        }
                    }
                    .onKeyPress(.upArrow) {
                        adjustBandwidth(by: 0.01)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustBandwidth(by: -0.01)
                        return .handled
                    }
            }
            .onAppear {
                bandwidthText = BandwidthConverter.formatForInput(q: q, mode: store.bandwidthDisplayMode)
            }
            .onChange(of: store.bandwidthDisplayMode) { _, newMode in
                bandwidthText = BandwidthConverter.formatForInput(q: q, mode: newMode)
            }

            Divider()

            Picker("Filter Type", selection: $filterType) {
                ForEach(FilterType.allCasesInUIOrder, id: \.self) { type in
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
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onAppear {
            focusedField = .gain
        }
    }

    private var bandwidthLabel: String {
        switch store.bandwidthDisplayMode {
        case .octaves:
            return "Bandwidth (oct)"
        case .qFactor:
            return "Q Factor"
        }
    }

    private func adjustGain(by delta: Float) {
        let current = Float(gainText) ?? gain
        let newGain = AudioConstants.clampGain(current + delta)
        gain = newGain
        gainText = String(format: "%.1f", newGain)
        gainUpdate(newGain)
    }

    private func adjustFrequency(by delta: Float) {
        let current = Float(frequencyText) ?? frequency
        let newFreq = AudioConstants.clampFrequency(current + delta)
        frequency = newFreq
        frequencyText = String(format: "%.0f", newFreq)
        frequencyUpdate(newFreq)
    }

    private func adjustBandwidth(by delta: Float) {
        guard let current = BandwidthConverter.parseInput(bandwidthText, mode: store.bandwidthDisplayMode) else { return }
        let newValue = current + delta

        let qValue: Float
        switch store.bandwidthDisplayMode {
        case .octaves:
            let clamped = BandwidthConverter.clampBandwidth(newValue)
            qValue = BandwidthConverter.bandwidthToQ(clamped)
        case .qFactor:
            qValue = BandwidthConverter.clampQ(newValue)
        }

        q = qValue
        bandwidthText = BandwidthConverter.formatForInput(q: qValue, mode: store.bandwidthDisplayMode)
        qUpdate(qValue)
    }
}

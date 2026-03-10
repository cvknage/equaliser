import AVFoundation
import SwiftUI

/// A fully parametric EQ band column.
struct EQBandSliderView: View {
    let index: Int
    let band: EQBandConfiguration
    @Binding var gain: Float
    let frequencyUpdate: (Float) -> Void
    let bandwidthUpdate: (Float) -> Void
    let filterTypeUpdate: (AVAudioUnitEQFilterType) -> Void
    let bypassUpdate: (Bool) -> Void

    /// Gain range in dB - references centralized range from EqualiserStore.
    private var minGain: Float { EqualiserStore.gainRange.lowerBound }
    private var maxGain: Float { EqualiserStore.gainRange.upperBound }

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

struct EQBandDetailPopover: View {
    @EnvironmentObject var store: EqualiserStore

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
                .font(.caption)

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
                            let clamped = min(max(value, EqualiserStore.gainRange.lowerBound), EqualiserStore.gainRange.upperBound)
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

import SwiftUI

struct LevelMetersView: View {
    let inputState: StereoMeterState
    let outputState: StereoMeterState
    let inputRMSState: StereoMeterState
    let outputRMSState: StereoMeterState

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Peak meters with scales on left
            StereoMeterGroup(title: "Peak In", state: inputState, showScale: true)
            StereoMeterGroup(title: "Peak Out", state: outputState, showScale: true)

            // RMS meters with scales on left
            StereoMeterGroupRMS(title: "RMS In", rmsState: inputRMSState, showScale: true)
            StereoMeterGroupRMS(title: "RMS Out", rmsState: outputRMSState, showScale: true)
        }
    }
}

struct GainControlsView: View {
    @Binding var inputGain: Float
    @Binding var outputGain: Float

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                Text("Gain In")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                GainStepperControl(gain: $inputGain)
            }

            VStack(spacing: 6) {
                Text("Gain Out")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                GainStepperControl(gain: $outputGain)
            }
        }
    }
}

struct StereoMeterGroup: View {
    let title: String
    let state: StereoMeterState
    var showScale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            HStack(alignment: .top, spacing: 4) {
                if showScale {
                    MeterScaleView(height: MeterConstants.meterHeight)
                }
                DualPeakMeterView(channelLabel: "L", state: state.left)
                DualPeakMeterView(channelLabel: "R", state: state.right)
            }
        }
    }
}

struct DualPeakMeterView: View {
    let channelLabel: String
    let state: ChannelMeterState

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
                        .fill(Color.gray.opacity(0.18))

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
            }
            .frame(width: 18, height: 126)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1)
            )

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
                        .fill(Color.gray.opacity(0.18))

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
            }
            .frame(width: 14, height: 126)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1)
            )

            Text(channelLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct StereoMeterGroupRMS: View {
    let title: String
    let rmsState: StereoMeterState
    var showScale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            HStack(alignment: .top, spacing: 4) {
                if showScale {
                    MeterScaleView(height: MeterConstants.meterHeight)
                }
                DualPeakRMSMeterView(channelLabel: "L", rmsState: rmsState.left)
                DualPeakRMSMeterView(channelLabel: "R", rmsState: rmsState.right)
            }
        }
    }
}

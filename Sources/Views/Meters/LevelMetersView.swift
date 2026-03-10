import SwiftUI

struct LevelMetersView: View {
    let meterStore: MeterStore
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            StereoMeterGroup(
                title: "Peak In",
                meterStore: meterStore,
                leftType: .inputPeakLeft,
                rightType: .inputPeakRight,
                showScale: true
            )
            StereoMeterGroup(
                title: "Peak Out",
                meterStore: meterStore,
                leftType: .outputPeakLeft,
                rightType: .outputPeakRight,
                showScale: true
            )
            
            StereoMeterGroupRMS(
                title: "RMS In",
                meterStore: meterStore,
                leftType: .inputRMSLeft,
                rightType: .inputRMSRight,
                showScale: true
            )
            StereoMeterGroupRMS(
                title: "RMS Out",
                meterStore: meterStore,
                leftType: .outputRMSLeft,
                rightType: .outputRMSRight,
                showScale: true
            )
        }
    }
}

struct GainControlsView: View {
    let inputGain: Float
    let outputGain: Float
    let onInputGainChange: (Float) -> Void
    let onOutputGainChange: (Float) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                Text("Gain In")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                GainStepperControl(
                    gain: inputGain,
                    onGainChange: onInputGainChange
                )
            }
            
            VStack(spacing: 6) {
                Text("Gain Out")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                GainStepperControl(
                    gain: outputGain,
                    onGainChange: onOutputGainChange
                )
            }
        }
    }
}

struct StereoMeterGroup: View {
    let title: String
    let meterStore: MeterStore
    let leftType: MeterType
    let rightType: MeterType
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
                PeakMeter(
                    channelLabel: "L",
                    meterStore: meterStore,
                    meterType: leftType
                )
                PeakMeter(
                    channelLabel: "R",
                    meterStore: meterStore,
                    meterType: rightType
                )
            }
        }
    }
}

struct PeakMeter: View {
    let channelLabel: String
    let meterStore: MeterStore
    let meterType: MeterType
    
    var body: some View {
        VStack(spacing: 4) {
            PeakMeterNSView(meterStore: meterStore, meterType: meterType)
                .frame(width: 18, height: 126)
            
            Text(channelLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct RMSMeter: View {
    let channelLabel: String
    let meterStore: MeterStore
    let meterType: MeterType
    
    var body: some View {
        VStack(spacing: 4) {
            RMSMeterNSView(meterStore: meterStore, meterType: meterType)
                .frame(width: 14, height: 126)
            
            Text(channelLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct StereoMeterGroupRMS: View {
    let title: String
    let meterStore: MeterStore
    let leftType: MeterType
    let rightType: MeterType
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
                RMSMeter(
                    channelLabel: "L",
                    meterStore: meterStore,
                    meterType: leftType
                )
                RMSMeter(
                    channelLabel: "R",
                    meterStore: meterStore,
                    meterType: rightType
                )
            }
        }
    }
}

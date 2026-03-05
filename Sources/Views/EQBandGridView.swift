import SwiftUI

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
                .padding(.horizontal)
            }
        }
    }
}

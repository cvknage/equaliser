import SwiftUI

struct GainStepperControl: View {
    @Binding var gain: Float
    let isActive: Bool

    var body: some View {
        VStack(spacing: 6) {
            StepperButton(symbol: "+", action: { adjustGain(by: 0.5) })
                .disabled(!isActive)

            InlineEditableValue(
                value: gain,
                displayFormatter: { String(format: "%+.1f dB", $0) },
                inputFormatter: { String(format: "%.1f", $0) },
                width: 54,
                alignment: .center,
                onCommit: { newValue in
                    gain = Self.roundToStep(EqualizerStore.clampGain(newValue))
                }
            )
            .onTapGesture(count: 2) {
                gain = 0
            }

            StepperButton(symbol: "-", action: { adjustGain(by: -0.5) })
                .disabled(!isActive)
        }
        .opacity(isActive ? 1 : 0.35)
    }

    private func adjustGain(by delta: Float) {
        let newValue = EqualizerStore.clampGain(gain + delta)
        gain = Self.roundToStep(newValue)
    }

    private static func roundToStep(_ value: Float) -> Float {
        (value * 2).rounded() / 2
    }
}

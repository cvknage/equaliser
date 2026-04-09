import SwiftUI

struct GainStepperControl: View {
    let gain: Float
    let onGainChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 12) {
            StepperButton(symbol: "+", action: { adjustGain(by: 0.5) })

            InlineEditableValue(
                value: gain,
                displayFormatter: { String(format: "%+.1f dB", $0) },
                inputFormatter: { String(format: "%.1f", $0) },
                width: 54,
                alignment: .center,
                onCommit: { newValue in
                    onGainChange(EqualiserStore.clampGain(newValue))
                }
            )
            .onTapGesture(count: 2) {
                onGainChange(0)
            }

            StepperButton(symbol: "-", action: { adjustGain(by: -0.5) })
        }
    }

    private func adjustGain(by delta: Float) {
        let snapped = Self.roundToStep(gain)
        let newValue = EqualiserStore.clampGain(snapped + delta)
        onGainChange(Self.roundToStep(newValue))
    }

    private static func roundToStep(_ value: Float) -> Float {
        (value * 2).rounded() / 2
    }
}

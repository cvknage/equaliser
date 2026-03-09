import SwiftUI

struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol == "+" ? "plus" : "minus")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

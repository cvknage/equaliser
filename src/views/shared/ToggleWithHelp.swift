import SwiftUI

/// A toggle with a question mark help button and popover.
struct ToggleWithHelp: View {
    let label: String
    @Binding var isOn: Bool
    let helpText: String
    @State private var showHelp = false
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(isDisabled)

            // Help icon
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp, arrowEdge: .trailing) {
                Text(helpText)
                    .font(.caption)
                    .padding(12)
                    .frame(width: 250)
            }
        }
    }
}

extension ToggleWithHelp {
    func disabled(_ disabled: Bool) -> some View {
        var view = self
        view.isDisabled = disabled
        return view
    }
}

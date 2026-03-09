import SwiftUI

/// Inline, tap-to-edit numeric value used for frequency/bandwidth fields.
struct InlineEditableValue: View {
    let value: Float
    let displayFormatter: (Float) -> String
    let inputFormatter: (Float) -> String
    let width: CGFloat
    let alignment: Alignment
    let onCommit: (Float) -> Void

    @State private var isEditing = false
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: width)
                    .focused($isFocused)
                    .onAppear {
                        text = inputFormatter(value)
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                    }
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
            } else {
                Text(displayFormatter(value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: width, alignment: alignment)
                    .onTapGesture {
                        text = inputFormatter(value)
                        isEditing = true
                    }
            }
        }
    }

    private func commit() {
        guard isEditing else { return }
        defer { isEditing = false }
        if let newValue = Float(text) {
            onCommit(newValue)
        }
    }
}

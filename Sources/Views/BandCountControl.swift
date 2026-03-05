import SwiftUI

struct BandCountControl: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var isEditing = false
    @State private var editedValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            StepperButton(symbol: "-", action: { adjustBands(by: -1) })

            // Tap-to-edit band count display
            if isEditing {
                TextField("", text: $editedValue)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                    }
                    .onSubmit(commit)
                    .onChange(of: editedValue) { _, newValue in
                        let digitsOnly = newValue.filter { $0.isNumber }
                        if digitsOnly != newValue {
                            editedValue = digitsOnly
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
            } else {
                Text("\(store.bandCount)")
                    .frame(width: 60)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editedValue = "\(store.bandCount)"
                        isEditing = true
                    }
            }

            StepperButton(symbol: "+", action: { adjustBands(by: 1) })
        }
        .onChange(of: store.bandCount) { _, newValue in
            // Always update display when value changes externally (e.g., preset load)
            editedValue = "\(newValue)"
            isEditing = false  // Exit edit mode when value changes externally
        }
    }

    private func adjustBands(by delta: Int) {
        let newCount = store.bandCount + delta
        applyBandCount(newCount)
    }

    private func commit() {
        guard isEditing else { return }
        defer { isEditing = false }
        if let value = Int(editedValue) {
            applyBandCount(value)
        } else {
            editedValue = "\(store.bandCount)"
        }
    }

    private func applyBandCount(_ count: Int) {
        let clamped = EQConfiguration.clampBandCount(count)
        store.bandCount = clamped
        editedValue = "\(clamped)"
    }
}

import SwiftUI
import AppKit

/// Inline, tap-to-edit numeric value used for frequency/bandwidth fields.
struct InlineEditableValue: View {
    let value: Float
    let displayFormatter: (Float) -> String
    let inputFormatter: (Float) -> String
    let width: CGFloat
    let alignment: Alignment
    let onCommit: (Float) -> Void
    var onNavigateLeft: (() -> Void)? = nil
    var onNavigateRight: (() -> Void)? = nil
    var startEditing: Bool = false

    @State private var isEditing = false
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var keyMonitor: Any? = nil

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
                        // Monitor for Shift+Tab
                        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
                                // Shift+Tab detected
                                if isEditing, let onNavigateLeft = onNavigateLeft {
                                    commit()
                                    onNavigateLeft()
                                }
                                return nil // Consume the event
                            }
                            return event
                        }
                    }
                    .onSubmit(commit)
                    .onChange(of: text) { _, newText in
                        if isEditing, let newValue = Float(newText) {
                            onCommit(newValue)
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
                    .onKeyPress(.tab) {
                        // Tab without Shift
                        if let onNavigateRight = onNavigateRight {
                            commit()
                            onNavigateRight()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        adjustValue(by: 0.1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustValue(by: -0.1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        commit()
                        return .handled
                    }
            } else {
                Text(displayFormatter(value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: width, alignment: alignment)
                    .onTapGesture {
                        text = inputFormatter(value)
                        isEditing = true
                    }
                    .onChange(of: startEditing) { _, shouldStart in
                        if shouldStart {
                            text = inputFormatter(value)
                            isEditing = true
                        }
                    }
            }
        }
        .onChange(of: value) { _, newValue in
            if isEditing {
                text = inputFormatter(newValue)
            }
        }
    }

    private func commit() {
        guard isEditing else { return }
        defer {
            isEditing = false
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        if let newValue = Float(text), newValue != value {
            onCommit(newValue)
        }
    }

    private func adjustValue(by delta: Float) {
        let currentValue = Float(text) ?? value
        let newValue = currentValue + delta
        text = inputFormatter(newValue)
    }
}

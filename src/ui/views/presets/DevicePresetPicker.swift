import AppKit
import SwiftUI

struct DevicePresetPicker: NSViewRepresentable {
    let names: [String]
    @Binding var selection: String?
    let label: String

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton()
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectPreset(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let titles = ["None"] + names
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
            for (index, name) in names.enumerated() {
                button.item(at: index + 1)?.representedObject = name
            }
        }
        let index = selection.flatMap { names.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        button.selectItem(at: index)
        button.setAccessibilityLabel(label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: 24)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String?>

        init(selection: Binding<String?>) {
            self.selection = selection
            super.init()
        }

        @objc func selectPreset(_ sender: NSPopUpButton) {
            selection.wrappedValue = sender.selectedItem?.representedObject as? String
        }
    }
}

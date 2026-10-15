import AppKit
import SwiftUI

/// Lets views outside the field insert tokens or text at the field's cursor.
@MainActor
final class DriverNameFormatFieldController: ObservableObject {
    fileprivate weak var coordinator: DriverNameFormatField.Coordinator?

    /// Inserts at the cursor (replacing any selection), or appends if the field was never edited.
    /// Returns `false` if the field is not on screen.
    @discardableResult
    func insert(_ segment: DriverNameFormat.Segment) -> Bool {
        guard let coordinator else { return false }
        coordinator.insert(segment)
        return true
    }
}

/// Token field for editing a `DriverNameFormat`: tokens show as bubbles, literal text as plain text.
struct DriverNameFormatField: NSViewRepresentable {
    @Binding var format: DriverNameFormat
    var controller: DriverNameFormatFieldController?

    /// Boxes a token so NSTokenField can tell it apart from literal text (a `String`).
    final class TokenObject: NSObject {
        let token: DriverNameFormat.Token
        init(_ token: DriverNameFormat.Token) { self.token = token }
    }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        // Only tokens inserted from the palette become bubbles; typed text stays one literal.
        field.tokenizingCharacterSet = CharacterSet(charactersIn: "\u{1}")
        field.tokenStyle = .rounded
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.objectValue = Self.objects(for: format)
        context.coordinator.lastReported = format
        context.coordinator.field = field
        controller?.coordinator = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        // A format the field did not report itself came from outside (Reset, token buttons).
        guard format != context.coordinator.lastReported else { return }
        if field.currentEditor() != nil {
            // Edits so far were already reported, so nothing is lost.
            field.abortEditing()
        }
        field.objectValue = Self.objects(for: format)
        context.coordinator.lastReported = format
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTokenField, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let height = nsView.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 22
        return CGSize(width: width, height: max(height, 22))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func objects(for format: DriverNameFormat) -> [Any] {
        format.segments.map { segment -> Any in
            switch segment {
            case .text(let text): text
            case .token(let token): TokenObject(token)
            }
        }
    }

    static func format(from objectValue: Any?) -> DriverNameFormat {
        let objects = objectValue as? [Any] ?? []
        return DriverNameFormat(segments: objects.compactMap { object in
            if let token = object as? TokenObject { return .token(token.token) }
            if let text = object as? String { return .text(text) }
            return nil
        })
    }

    @MainActor
    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: DriverNameFormatField
        /// The last format this field produced or displayed.
        var lastReported: DriverNameFormat?
        weak var field: NSTokenField?
        /// Cursor or selection when editing last ended, in editor units.
        private var lastSelection: NSRange?

        init(parent: DriverNameFormatField) {
            self.parent = parent
        }

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            (representedObject as? TokenObject)?.token.displayName ?? representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
            representedObject is TokenObject ? .rounded : .none
        }

        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
            representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
            editingString
        }

        func controlTextDidChange(_ notification: Notification) {
            push(notification)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView {
                lastSelection = editor.selectedRange()
            }
            push(notification)
        }

        func insert(_ segment: DriverNameFormat.Segment) {
            guard let field else { return }
            let current = parent.format
            let selection = (field.currentEditor() as? NSTextView)?.selectedRange()
                ?? lastSelection
                ?? NSRange(location: current.editorLength, length: 0)
            let lower = min(selection.location, current.editorLength)
            let upper = min(selection.location + selection.length, current.editorLength)
            let updated = current.replacing(lower..<upper, with: segment)

            if field.currentEditor() != nil {
                field.abortEditing()
            }
            field.objectValue = DriverNameFormatField.objects(for: updated)
            lastReported = updated
            parent.format = updated

            // Put the cursor right after the insertion so typing continues there.
            let cursor = NSRange(location: lower + segment.editorLength, length: 0)
            lastSelection = cursor
            if field.window?.makeFirstResponder(field) == true {
                (field.currentEditor() as? NSTextView)?.setSelectedRange(cursor)
            }
        }

        private func push(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            let format = DriverNameFormatField.format(from: field.objectValue)
            lastReported = format
            if format != parent.format {
                parent.format = format
            }
        }
    }
}

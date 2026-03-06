import SwiftUI
import AppKit

/// A view that captures its containing NSWindow and passes it to a callback.
/// Use this to get a reference to the parent window for visibility checking.
struct WindowAccessor: NSViewRepresentable {
    let onWindowFound: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The window will be available after the view is added to the view hierarchy
        DispatchQueue.main.async {
            self.onWindowFound(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update the window reference if it changes
        onWindowFound(nsView.window)
    }
}

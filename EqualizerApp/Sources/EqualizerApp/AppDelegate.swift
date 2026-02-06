import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    let audioEngine = AudioEngineManager()
    weak var store: EqualizerStore? {
        didSet { updatePopoverRootView() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Equalizer")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 480)
        updatePopoverRootView()
    }

    private func updatePopoverRootView() {
        if let store {
            popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(store))
        } else {
            popover.contentViewController = NSHostingController(rootView: ContentView())
        }
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

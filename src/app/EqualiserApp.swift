import SwiftUI

// MARK: - Application Delegate

@MainActor
final class EqualiserAppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: EqualiserStore?
    private var rightClickMonitor: Any?

    func setStore(_ store: EqualiserStore) {
        self.store = store
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseDown, handler: Self.handleRightClick
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
    }

    static func handleRightClick(_ event: NSEvent) -> NSEvent? {
        var view = event.window?.contentView?.hitTest(event.locationInWindow)
        while let currentView = view {
            if let button = currentView as? NSStatusBarButton {
                button.performClick(nil)
                return nil
            }
            view = currentView.superview
        }
        return event
    }
}

// MARK: - Main App

@main
struct EqualiserMain: App {
    @StateObject private var store = EqualiserStore()
    @StateObject private var windowActivation = WindowActivationController()
    @NSApplicationDelegateAdaptor(EqualiserAppDelegate.self) var appDelegate

    init() {
        // IMPORTANT: Do NOT access @StateObject (self.store) here.
        // SwiftUI initializes @StateObject AFTER init() completes.
        // Accessing it in init() causes SwiftUI to create two instances.
        // Wire appDelegate.setStore(store) in body using .onAppear instead.

        // Note: Microphone permission is NOT requested here.
        // It's only requested when needed (HAL input capture mode or manual mode).
        // Shared memory capture (default) does NOT require microphone permission.
    }

    var body: some Scene {
        // Main EQ settings window (hidden by default, opened on demand)
        Window("Equaliser", id: "equaliser") {
            EQWindowView()
                .environmentObject(store)
                .environmentObject(windowActivation)
        }
        .defaultPosition(.center)
        .defaultSize(width: 1060, height: 530)
        .windowResizability(.contentMinSize)
        .commands {
            // Cmd+B: Toggle bypass
            CommandGroup(replacing: .toolbar) {
                Button("Toggle Bypass") {
                    store.isBypassed.toggle()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Save Preset") {
                    NotificationCenter.default.post(name: .savePresetShortcut, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }

        // Menu bar popover (always available)
        MenuBarExtra("Equaliser", systemImage: "slider.vertical.3") {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(windowActivation)
                .onAppear {
                    windowActivation.launchAsMenuBarApp()
                    // Wire up appDelegate reference after @StateObject is initialized.
                    // MenuBarExtra is always visible, so this will always fire.
                    appDelegate.setStore(store)
                }
        }
        .menuBarExtraStyle(.window)

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(windowActivation)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let savePresetShortcut = Notification.Name("savePresetShortcut")
}

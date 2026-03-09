import AVFoundation
import SwiftUI

@main
struct EqualiserAppMain: App {
    @StateObject private var store = EqualiserStore()

    init() {
        // Hide dock icon permanently - this is a menu bar app
        // Defer until NSApp is available (it's nil during init)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }

        // Request microphone access for audio routing
        AVAudioApplication.requestRecordPermission { granted in
            if !granted {
                assertionFailure("Microphone access denied. Audio routing will be unavailable.")
            }
        }
    }

    var body: some Scene {
        // Main EQ settings window (hidden by default, opened on demand)
        Window("Equaliser", id: "equaliser") {
            EQWindowView()
                .environmentObject(store)
        }
        .defaultPosition(.center)
        .defaultSize(width: 1060, height: 530)
        .windowResizability(.contentMinSize)

        // Menu bar popover (always available)
        MenuBarExtra("Equaliser", systemImage: "slider.vertical.3") {
            MenuBarContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

import SwiftUI

@main
struct EqualizerAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = EqualizerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    if appDelegate.store !== store {
                        appDelegate.store = store
                    }
                    if store.audioEngine !== appDelegate.audioEngine {
                        store.audioEngine = appDelegate.audioEngine
                        store.audioEngine?.start()
                    }
                }
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.largeTitle)
            Text("Equalizer coming soon")
                .font(.headline)
        }
        .padding()
        .frame(width: 280, height: 200)
    }
}

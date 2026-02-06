import SwiftUI

@main
struct EqualizerAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
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

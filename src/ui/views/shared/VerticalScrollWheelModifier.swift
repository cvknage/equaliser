import AppKit
import SwiftUI

extension View {
    /// Handles vertical scrolling while the pointer is over this view.
    func onVerticalScrollWheel(_ action: @escaping (NSEvent) -> Void) -> some View {
        modifier(VerticalScrollWheelModifier(action: action))
    }
}

private struct VerticalScrollWheelModifier: ViewModifier {
    let action: (NSEvent) -> Void

    @State private var isPointerInside = false
    @State private var eventMonitor: Any?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { isPointerInside = $0 }
            .onAppear(perform: installEventMonitor)
            .onDisappear(perform: removeEventMonitor)
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let isVertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            guard isPointerInside, isVertical, event.scrollingDeltaY != 0 else {
                return event
            }

            action(event)
            return nil
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}

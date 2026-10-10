import AppKit
import SwiftUI
import XCTest
@testable import Equaliser

@MainActor
final class DevicePresetPickerTests: XCTestCase {
    func testControlWidthDoesNotDependOnSelectedTitle() throws {
        for selection in [nil, "Flat", "A much longer preset name"] as [String?] {
            let host = NSHostingView(rootView: DevicePresetPicker(
                names: ["Flat", "A much longer preset name"],
                selection: .constant(selection),
                label: "Preset for speakers"
            ).frame(width: 160, height: 24))
            host.frame = NSRect(x: 0, y: 0, width: 160, height: 24)
            host.layoutSubtreeIfNeeded()

            let button = try XCTUnwrap(popup(in: host))
            XCTAssertEqual(button.frame.width, 160, accuracy: 1)
            XCTAssertEqual(button.title, selection ?? "None")
        }
    }

    func testSelectingPresetAndNoneUpdatesBinding() throws {
        var selection: String? = "Flat"
        let host = NSHostingView(rootView: DevicePresetPicker(
            names: ["Flat", "DUSK"],
            selection: Binding(get: { selection }, set: { selection = $0 }),
            label: "Preset for headphones"
        ).frame(width: 160, height: 24))
        host.frame = NSRect(x: 0, y: 0, width: 160, height: 24)
        host.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(popup(in: host))

        button.selectItem(at: 2)
        button.sendAction(button.action, to: button.target)
        XCTAssertEqual(selection, "DUSK")
        XCTAssertEqual(button.frame.width, 160, accuracy: 1)

        button.selectItem(at: 0)
        button.sendAction(button.action, to: button.target)
        XCTAssertNil(selection)
        XCTAssertEqual(button.frame.width, 160, accuracy: 1)
    }

    private func popup(in view: NSView) -> NSPopUpButton? {
        if let button = view as? NSPopUpButton { return button }
        return view.subviews.lazy.compactMap { self.popup(in: $0) }.first
    }
}

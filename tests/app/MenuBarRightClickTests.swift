import AppKit
import XCTest
@testable import Equaliser

@MainActor
final class MenuBarRightClickTests: XCTestCase {
    func testRightClickOnStatusBarButtonPerformsClickAndConsumesEvent() throws {
        let target = ClickTarget()
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.target = target
        button.action = #selector(ClickTarget.click)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(button)

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: NSPoint(x: 12, y: 12),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        let returnedEvent = EqualiserAppDelegate.handleRightClick(event)

        XCTAssertNil(returnedEvent)
        XCTAssertEqual(target.clickCount, 1)
    }

    func testRightClickOutsideStatusBarButtonPassesThrough() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: NSPoint(x: 12, y: 12),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        let returnedEvent = EqualiserAppDelegate.handleRightClick(event)

        XCTAssertTrue(returnedEvent === event)
    }
}

@MainActor
private final class ClickTarget: NSObject {
    private(set) var clickCount = 0

    @objc func click() {
        clickCount += 1
    }
}

import AppKit
@testable import ScreenText
import SwiftUI
import Testing

@MainActor
struct CaptureToolbarWindowTests {
    @Test func `positions toolbar on displays in every direction`() {
        let size = NSSize(width: 260, height: 50)
        let frames = [
            NSRect(x: 0, y: 0, width: 1440, height: 875),
            NSRect(x: -1920, y: 0, width: 1920, height: 1055),
            NSRect(x: 1440, y: -1080, width: 1920, height: 1055),
            NSRect(x: 0, y: 900, width: 1440, height: 875),
        ]
        for visibleFrame in frames {
            let toolbarFrame = CaptureToolbarWindow.positionedFrame(size: size, visibleFrame: visibleFrame)
            #expect(toolbarFrame.midX == visibleFrame.midX)
            #expect(toolbarFrame.minY == visibleFrame.minY + 24)
            #expect(visibleFrame.contains(toolbarFrame))
        }
    }

    @Test func `showing toolbar sets cursor and hover keeps arrow across mode changes`() throws {
        let panel = CaptureToolbarWindow()
        defer { panel.hide(); NSCursor.arrow.set() }
        let display = SelectionDisplay(id: 1, frame: .init(x: -10000, y: -10000, width: 600, height: 400),
                                       visibleFrame: .init(x: -10000, y: -10000, width: 600, height: 400))
        #expect(panel.show(display: display, mode: .box, onAction: { _ in }))
        #expect(NSCursor.current == .crosshair)
        let view = try #require(panel.contentView)
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
                                                    modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                    context: nil,
                                                    eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseEntered(with: event)
        #expect(NSCursor.current == .arrow)
        panel.setMode(.freehand)
        #expect((panel.contentView as? NSHostingView<CaptureToolbarView>)?.rootView.mode == .freehand)
        #expect(NSCursor.current == .arrow)
        panel.setMode(.box)
        #expect((panel.contentView as? NSHostingView<CaptureToolbarView>)?.rootView.mode == .box)
        #expect(NSCursor.current == .arrow)
        view.mouseExited(with: event)
        #expect(NSCursor.current == .crosshair)
    }

    @Test func `panel is transparent floating and does not become the main window`() {
        let panel = CaptureToolbarWindow()
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.level == .floating)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }
}

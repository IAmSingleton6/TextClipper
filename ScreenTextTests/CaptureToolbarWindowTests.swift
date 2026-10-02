import AppKit
@testable import ScreenText
import SwiftUI
import Testing

extension DesktopTests {
    @MainActor
    struct CaptureToolbarWindowTests {
        @Test(arguments: [
            CGRect(x: 0, y: 0, width: 1440, height: 875),
            CGRect(x: -1920, y: 0, width: 1920, height: 1055),
            CGRect(x: 1440, y: -1080, width: 1920, height: 1055),
            CGRect(x: 0, y: 900, width: 1440, height: 875),
        ])
        func `toolbar stays centered above the bottom of each display`(visibleFrame: CGRect) {
            // WHEN
            let frame = CaptureToolbarWindow.positionedFrame(
                size: .init(width: 260, height: 50),
                visibleFrame: ScreenRect(appKitGlobalRect: visibleFrame),
            )

            // THEN
            #expect(frame.midX == visibleFrame.midX)
            #expect(frame.minY == visibleFrame.minY + 24)
            #expect(visibleFrame.contains(frame.appKitGlobalRect))
        }

        @Test func `showing a toolbar away from the pointer selects the capture crosshair`() throws {
            let toolbar = ToolbarFixture()

            // WHEN
            try toolbar.show()

            // THEN
            #expect(NSCursor.current == .crosshair)
        }

        @Test(arguments: [CaptureMode.box, .freehand])
        func `hovering the toolbar keeps the arrow when capture mode changes`(mode: CaptureMode) throws {
            let toolbar = ToolbarFixture(initialMode: mode == .box ? .freehand : .box)

            // GIVEN
            try toolbar.show()
            try toolbar.enter()
            #expect(NSCursor.current == .arrow)

            // WHEN
            toolbar.panel.setMode(mode)

            // THEN
            #expect((toolbar.panel.contentView as? NSHostingView<CaptureToolbarView>)?.rootView.mode == mode)
            #expect(NSCursor.current == .arrow)
        }

        @Test func `leaving the toolbar restores the capture crosshair`() throws {
            let toolbar = ToolbarFixture()

            // GIVEN
            try toolbar.show()
            try toolbar.enter()

            // WHEN
            try toolbar.exit()

            // THEN
            #expect(NSCursor.current == .crosshair)
        }

        @Test func `hiding the toolbar releases its view and cursor exclusion`() throws {
            let toolbar = ToolbarFixture()

            // GIVEN
            try toolbar.show()
            #expect(toolbar.panel.cursorExclusionRect != nil)

            // WHEN
            toolbar.panel.hide()

            // THEN
            #expect(!toolbar.panel.isVisible)
            #expect(toolbar.panel.contentView == nil)
            #expect(toolbar.panel.cursorExclusionRect == nil)
        }

        @Test func `toolbar panels float transparently without becoming the main window`() {
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
}

@MainActor
private final class ToolbarFixture {
    let panel = CaptureToolbarWindow()
    private let initialMode: CaptureMode
    private let display = SelectionDisplay(id: 1, frame: .init(x: -10000, y: -10000, width: 600, height: 400),
                                           visibleFrame: .init(x: -10000, y: -10000, width: 600, height: 400))

    init(initialMode: CaptureMode = .box) {
        self.initialMode = initialMode
    }

    func show() throws {
        try #require(self.panel.show(display: self.display, mode: self.initialMode, onAction: { _ in
        }))
    }

    func enter() throws {
        try self.view.mouseEntered(with: self.event())
    }

    func exit() throws {
        try self.view.mouseExited(with: self.event())
    }

    private var view: NSView {
        get throws { try #require(self.panel.contentView) }
    }

    private func event() throws -> NSEvent {
        try NativeMouse.event(.mouseMoved, at: .zero, window: self.panel)
    }

    isolated deinit {
        panel.hide()
        NSCursor.arrow.set()
    }
}

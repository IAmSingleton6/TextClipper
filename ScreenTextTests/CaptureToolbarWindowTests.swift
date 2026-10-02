import AppKit
import Testing
@testable import ScreenText

@Suite @MainActor
struct CaptureToolbarWindowTests {
    @Test func positionsToolbarOnDisplaysInEveryDirection() {
        let size = NSSize(width: 260, height: 50)
        let frames = [
            NSRect(x: 0, y: 0, width: 1440, height: 875),
            NSRect(x: -1920, y: 0, width: 1920, height: 1055),
            NSRect(x: 1440, y: -1080, width: 1920, height: 1055),
            NSRect(x: 0, y: 900, width: 1440, height: 875)
        ]
        for visibleFrame in frames {
            let toolbarFrame = CaptureToolbarWindow.positionedFrame(size: size, visibleFrame: visibleFrame)
            #expect(toolbarFrame.midX == visibleFrame.midX)
            #expect(toolbarFrame.minY == visibleFrame.minY + 24)
            #expect(visibleFrame.contains(toolbarFrame))
        }
    }

    @Test func panelIsTransparentFloatingAndDoesNotBecomeTheMainWindow() {
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

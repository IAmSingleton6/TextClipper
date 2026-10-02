import AppKit
@testable import ScreenText
import Testing

private let layouts = [
    CGRect(x: 0, y: 0, width: 1200, height: 800),
    CGRect(x: -1200, y: 0, width: 1200, height: 800),
    CGRect(x: 1200, y: -800, width: 1200, height: 800),
    CGRect(x: 0, y: 800, width: 1200, height: 800),
    CGRect(x: -300, y: -800, width: 1200, height: 800),
]
private let displays = layouts.enumerated().map { SelectionDisplay(
    id: UInt32($0.offset + 1), frame: ScreenRect(appKitGlobalRect: $0.element),
    visibleFrame: ScreenRect(appKitGlobalRect: $0.element),
) }
private let directions = [
    (CGPoint(x: 100, y: 50), CGPoint(x: 300, y: 250)),
    (CGPoint(x: 300, y: 250), CGPoint(x: 100, y: 50)),
    (CGPoint(x: 300, y: 50), CGPoint(x: 100, y: 250)),
    (CGPoint(x: 100, y: 250), CGPoint(x: 300, y: 50)),
]
private let dragCases = [CaptureMode.box, .freehand].flatMap { mode in
    directions.map { NativeDragCase(mode: mode, start: $0.0, end: $0.1) }
}

private struct NativeDragCase {
    let mode: CaptureMode
    let start: CGPoint
    let end: CGPoint
}

extension DesktopTests {
    @MainActor
    struct MultiDisplayTests {
        @Test(arguments: displays)
        func `a cursor inside a display selects that display`(display: SelectionDisplay) {
            let point = ScreenPoint(x: display.frame.midX, y: display.frame.midY)
            #expect(SelectionDisplay.containing(point, in: displays)?.id == display.id)
        }

        @Test(arguments: [
            (ScreenPoint(x: 0, y: 400), UInt32(1)), (.init(x: -0.01, y: 400), UInt32(2)),
            (.init(x: 600, y: 800), UInt32(4)), (.init(x: 1200, y: -400), UInt32(3)),
        ])
        func `shared display boundaries have a deterministic owner`(cursor: (ScreenPoint, UInt32)) {
            #expect(SelectionDisplay.containing(cursor.0, in: displays)?.id == cursor.1)
        }

        @Test(arguments: [ScreenPoint(x: 3000, y: 3000), .init(x: .nan, y: 0)])
        func `cursors in gaps or at invalid coordinates select no display`(point: ScreenPoint) {
            #expect(SelectionDisplay.containing(point, in: displays) == nil)
        }

        @Test func `no display can be selected from an empty layout`() {
            #expect(SelectionDisplay.containing(.zero, in: []) == nil)
        }

        @Test(arguments: layouts, dragCases)
        private func `native drags stay display local across layouts modes and directions`(
            frame: CGRect,
            drag: NativeDragCase,
        ) throws {
            let selection = SelectionFixture(display: SelectionDisplay(
                id: 42, frame: ScreenRect(appKitGlobalRect: frame),
                visibleFrame: ScreenRect(appKitGlobalRect: frame.insetBy(dx: 0, dy: 20)),
            ), initialMode: drag.mode, onEvent: { selection, event in
                if case .completed = event {
                    #expect(selection.manager.window == nil)
                }
            })

            // GIVEN
            try selection.start()
            #expect(try selection.window.frame == frame)
            try selection.press(at: drag.start)
            if drag.mode == .freehand {
                try selection.drag(to: .init(x: drag.end.x, y: drag.start.y))
            }
            try selection.drag(to: drag.end)

            // WHEN
            try selection.release(at: drag.end)

            // THEN
            let result = try #require(selection.completed.first)
            #expect(result.displayID == 42)
            #expect(result.rect == DisplayRect(x: 100, y: 50, width: 200, height: 200))
            #expect(selection.cancellations == 0)
            switch result.shape {
            case .rectangle: #expect(drag.mode == .box)
            case .freehand: #expect(drag.mode == .freehand)
            }
        }

        @Test(arguments: [CGFloat(1), 1.25, 1.5, 2, 3])
        func `the full display and all four corners convert at the requested scale`(scale: CGFloat) throws {
            // GIVEN
            let points = CGSize(width: 1200, height: 800)
            let pixels = try ScreenshotSizing.requestedPixelSize(forDisplayPointSize: points, pointPixelScale: scale)
            let crops: [(DisplayRect, CGRect)] = [
                (.init(x: 0, y: 0, width: 1200, height: 800), CGRect(origin: .zero, size: pixels)),
                (
                    .init(x: 0, y: 0, width: 100, height: 100),
                    .init(x: 0, y: 700 * scale, width: 100 * scale, height: 100 * scale),
                ),
                (
                    .init(x: 1100, y: 700, width: 100, height: 100),
                    .init(x: 1100 * scale, y: 0, width: 100 * scale, height: 100 * scale),
                ),
                (
                    .init(x: 0, y: 700, width: 100, height: 100),
                    .init(x: 0, y: 0, width: 100 * scale, height: 100 * scale),
                ),
                (
                    .init(x: 1100, y: 0, width: 100, height: 100),
                    .init(x: 1100 * scale, y: 700 * scale, width: 100 * scale, height: 100 * scale),
                ),
            ]
            for (selection, expected) in crops {
                // WHEN
                let crop = try ImageCoordinates.toPixelRect(from: selection, displaySize: points, imageSize: pixels)

                // THEN
                #expect(crop == ImagePixelRect(cgImageCropRect: expected))
            }
        }

        @Test func `native overlays include the menu bar on every connected display`() throws {
            let screens = NSScreen.screens
            try #require(!screens.isEmpty)
            for screen in screens {
                // GIVEN
                let number = try #require(screen
                    .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                let selection = SelectionFixture(display: SelectionDisplay(
                    id: number.uint32Value, frame: ScreenRect(appKitGlobalRect: screen.frame),
                    visibleFrame: ScreenRect(appKitGlobalRect: screen.visibleFrame),
                ))

                // WHEN
                try selection.start()

                // THEN
                #expect(try selection.window.frame == screen.frame)
                #expect(try selection.view.bounds == CGRect(origin: .zero, size: screen.frame.size))
                let pixels = try ScreenshotSizing.requestedPixelSize(forDisplayPointSize: screen.frame.size,
                                                                     pointPixelScale: screen.backingScaleFactor)
                #expect(pixels.width == ceil(screen.frame.width * screen.backingScaleFactor))
                #expect(pixels.height == ceil(screen.frame.height * screen.backingScaleFactor))
                selection.hide()
            }
        }

        @Test(arguments: [CaptureState.toolbar, .selecting(.box)])
        func `layout changes cancel visible capture UI`(state: CaptureState) {
            let capture = CaptureFixture()
            let center = NotificationCenter()
            let observer = DisplayConfigurationObserver(center: center) { capture.cancel() }
            defer { withExtendedLifetime(observer) {} }

            // GIVEN
            capture.start()
            if state != .toolbar {
                capture.beginSelection()
            }

            // WHEN
            center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

            // THEN
            #expect(capture.isIdle)
            #expect(!capture.toolbarIsVisible)
            #expect(!capture.selectionIsVisible)
            #expect(capture.results.isEmpty)
        }

        @Test func `layout changes discard pending capture without copying`() async throws {
            let service = SuspendedCaptureService()
            let clipboard = TestClipboardWriter()
            let capture = CaptureFixture(captureService: service, clipboardService: clipboard)
            let center = NotificationCenter()
            let observer = DisplayConfigurationObserver(center: center) { capture.cancel() }
            defer { withExtendedLifetime(observer) {} }

            // GIVEN
            capture.start()
            capture.beginSelection()
            capture.completeSelection()
            try await service.waitUntilStarted()

            // WHEN
            center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try await service.finish(.success(TestImages.colored()))
            try await capture.waitForProcessingToReturn()

            // THEN
            #expect(capture.isIdle)
            #expect(capture.results.isEmpty)
            #expect(clipboard.texts.isEmpty)
            #expect(clipboard.attempts.isEmpty)
        }
    }
}

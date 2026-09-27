import AppKit
import Testing
@testable import ScreenText

private let layouts = [
    CGRect(x: 0, y: 0, width: 1200, height: 800),
    CGRect(x: -1200, y: 0, width: 1200, height: 800),
    CGRect(x: 1200, y: -800, width: 1200, height: 800),
    CGRect(x: 0, y: 800, width: 1200, height: 800),
    CGRect(x: -300, y: -800, width: 1200, height: 800)
]

@Suite @MainActor
struct MultiDisplayTests {
    @Test func choosesCursorDisplayAcrossBoundariesAndGaps() {
        let displays = layouts.enumerated().map { SelectionDisplay(id: UInt32($0.offset + 1), frame: $0.element, visibleFrame: $0.element) }
        for display in displays {
            let result = SelectionDisplay.containing(CGPoint(x: display.frame.midX, y: display.frame.midY), in: displays)
            #expect(result?.id == display.id)
        }
        #expect(SelectionDisplay.containing(CGPoint(x: 0, y: 400), in: displays)?.id == 1)
        #expect(SelectionDisplay.containing(CGPoint(x: -0.01, y: 400), in: displays)?.id == 2)
        #expect(SelectionDisplay.containing(CGPoint(x: 600, y: 800), in: displays)?.id == 4)
        #expect(SelectionDisplay.containing(CGPoint(x: 1200, y: -400), in: displays)?.id == 3)
        #expect(SelectionDisplay.containing(CGPoint(x: 3000, y: 3000), in: displays) == nil)
        #expect(SelectionDisplay.containing(CGPoint(x: CGFloat.nan, y: 0), in: displays) == nil)
        #expect(SelectionDisplay.containing(.zero, in: []) == nil)
    }

    @Test(arguments: layouts)
    func nativeDragsRemainDisplayLocalInEveryDirection(frame: CGRect) throws {
        let display = SelectionDisplay(id: 42, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 20))
        let corners = [
            (CGPoint(x: 100, y: 50), CGPoint(x: 300, y: 250)),
            (CGPoint(x: 300, y: 250), CGPoint(x: 100, y: 50)),
            (CGPoint(x: 300, y: 50), CGPoint(x: 100, y: 250)),
            (CGPoint(x: 100, y: 250), CGPoint(x: 300, y: 50))
        ]
        let manager = SelectionManager()
        defer { manager.hide() }
        for mode in [CaptureMode.box, .freehand] {
            for (start, end) in corners {
                var result: Selection?
                let prepared = manager.prepare(display: display, mode: mode, onStarted: {}, onCompleted: {
                    #expect(manager.window == nil)
                    result = $0
                }, onCancelled: { Issue.record("Valid drag was cancelled") })
                #expect(prepared)
                let window = try #require(manager.window)
                #expect(window.frame == frame)
                let event = { (type: NSEvent.EventType, point: CGPoint) in
                    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                window.selectionView.mouseDown(with: event(.leftMouseDown, start))
                if mode == .freehand {
                    window.selectionView.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: end.x, y: start.y)))
                }
                window.selectionView.mouseDragged(with: event(.leftMouseDragged, end))
                window.selectionView.mouseUp(with: event(.leftMouseUp, end))
                #expect(result?.displayID == 42)
                #expect(result?.rect == CGRect(x: 100, y: 50, width: 200, height: 200))
                #expect(result.map { mode.accepts($0.shape) } == true)
            }
        }
    }

    @Test(arguments: [CGFloat(1), 1.25, 1.5, 2, 3])
    func scalesCornersAndEntireDisplayWithoutGlobalOrigin(scale: CGFloat) throws {
        let converter = DisplayCoordinateConverter()
        let points = CGSize(width: 1200, height: 800)
        let pixels = try converter.imageSize(displaySize: points, pixelScale: scale)
        #expect(try converter.pixelRect(for: CGRect(origin: .zero, size: points), displaySize: points, imageSize: pixels)
                == CGRect(origin: .zero, size: pixels))
        #expect(try converter.pixelRect(for: CGRect(x: 0, y: 0, width: 100, height: 100), displaySize: points, imageSize: pixels)
                == CGRect(x: 0, y: 700 * scale, width: 100 * scale, height: 100 * scale))
        #expect(try converter.pixelRect(for: CGRect(x: 1100, y: 700, width: 100, height: 100), displaySize: points, imageSize: pixels)
                == CGRect(x: 1100 * scale, y: 0, width: 100 * scale, height: 100 * scale))
    }

    @Test func overlaysMatchConnectedDisplaysIncludingMenuBar() throws {
        let manager = SelectionManager()
        defer { manager.hide() }
        for screen in NSScreen.screens {
            let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            let display = SelectionDisplay(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
            let prepared = manager.prepare(display: display, mode: .box, onStarted: {}, onCompleted: { _ in }, onCancelled: {})
            #expect(prepared)
            #expect(manager.window?.frame == screen.frame)
            #expect(manager.window?.selectionView.bounds == CGRect(origin: .zero, size: screen.frame.size))
            let pixels = try DisplayCoordinateConverter().imageSize(displaySize: screen.frame.size, pixelScale: screen.backingScaleFactor)
            #expect(pixels.width == ceil(screen.frame.width * screen.backingScaleFactor))
            #expect(pixels.height == ceil(screen.frame.height * screen.backingScaleFactor))
            manager.hide()
        }
    }

    @Test func invalidAndOverflowedGeometryIsRejected() {
        let converter = DisplayCoordinateConverter()
        let size = CGSize(width: 100, height: 100)
        #expect(!Selection.isValid(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)))
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try converter.pixelRect(for: CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 10), displaySize: size, imageSize: size)
        }
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try converter.pixelRect(for: CGRect(x: 0, y: 0, width: 1, height: 1), displaySize: CGSize(width: CGFloat.leastNonzeroMagnitude, height: 1), imageSize: size)
        }
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try converter.imageSize(displaySize: CGSize(width: CGFloat.leastNonzeroMagnitude, height: 1), pixelScale: CGFloat.leastNonzeroMagnitude)
        }
    }

    @Test func layoutChangeCancelsOverlayAndDiscardsPendingCapture() async throws {
        let center = NotificationCenter()
        let service = SuspendedCaptureService()
        let manager = TestSelectionManager()
        let toolbar = TestCaptureToolbar()
        let clipboard = TestClipboardWriter()
        let display = SelectionDisplay(id: 1, frame: layouts[0], visibleFrame: layouts[0])
        let controller = CaptureController(clipboardService: clipboard, ocrService: TestTextRecognizer(),
            captureService: service, toolbar: toolbar, selectionManager: manager, displayProvider: { display })
        let observer = DisplayConfigurationObserver(center: center) { controller.cancel() }
        let selection = Selection(displayID: 1, rect: CGRect(x: 10, y: 10, width: 100, height: 60), shape: .rectangle)
        controller.onTextRecognized = { _ in Issue.record("Stale display result was delivered") }
        controller.start()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(controller.state == .idle && !toolbar.isVisible && !manager.isVisible)
        controller.start()
        manager.onStarted?()
        manager.onCompleted?(selection)
        for _ in 0..<100 where !(await service.started) { try await Task.sleep(for: .milliseconds(2)) }
        try #require(await service.started)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await service.finish(.success(try await TestScreenCaptureService().capture(region: selection)))
        try await Task.sleep(for: .milliseconds(20))
        #expect(controller.state == .idle && clipboard.texts.isEmpty)
        withExtendedLifetime(observer) {}
    }
}

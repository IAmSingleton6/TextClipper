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

@MainActor
struct MultiDisplayTests {
    @Test func `chooses cursor display across boundaries and gaps`() {
        let displays = layouts.enumerated().map { SelectionDisplay(
            id: UInt32($0.offset + 1),
            frame: ScreenRect(appKitGlobalRect: $0.element),
            visibleFrame: ScreenRect(appKitGlobalRect: $0.element),
        ) }
        for display in displays {
            let result = SelectionDisplay.containing(
                ScreenPoint(appKitGlobalPoint: CGPoint(x: display.frame.midX, y: display.frame.midY)),
                in: displays,
            )
            #expect(result?.id == display.id)
        }
        #expect(SelectionDisplay.containing(ScreenPoint(appKitGlobalPoint: CGPoint(x: 0, y: 400)), in: displays)?
            .id == 1)
        #expect(SelectionDisplay.containing(ScreenPoint(appKitGlobalPoint: CGPoint(x: -0.01, y: 400)), in: displays)?
            .id == 2)
        #expect(SelectionDisplay.containing(ScreenPoint(appKitGlobalPoint: CGPoint(x: 600, y: 800)), in: displays)?
            .id == 4)
        #expect(SelectionDisplay.containing(ScreenPoint(appKitGlobalPoint: CGPoint(x: 1200, y: -400)), in: displays)?
            .id == 3)
        #expect(SelectionDisplay
            .containing(ScreenPoint(appKitGlobalPoint: CGPoint(x: 3000, y: 3000)), in: displays) == nil)
        #expect(SelectionDisplay.containing(
            ScreenPoint(appKitGlobalPoint: CGPoint(x: CGFloat.nan, y: 0)),
            in: displays,
        ) == nil)
        #expect(SelectionDisplay.containing(.zero, in: []) == nil)
    }

    @Test(arguments: layouts)
    func `native drags remain display local in every direction`(frame: CGRect) throws {
        let display = SelectionDisplay(
            id: 42,
            frame: ScreenRect(appKitGlobalRect: frame),
            visibleFrame: ScreenRect(appKitGlobalRect: frame.insetBy(dx: 0, dy: 20)),
        )
        let corners = [
            (CGPoint(x: 100, y: 50), CGPoint(x: 300, y: 250)),
            (CGPoint(x: 300, y: 250), CGPoint(x: 100, y: 50)),
            (CGPoint(x: 300, y: 50), CGPoint(x: 100, y: 250)),
            (CGPoint(x: 100, y: 250), CGPoint(x: 300, y: 50)),
        ]
        let manager = SelectionManager()
        defer { manager.hide() }
        for mode in [CaptureMode.box, .freehand] {
            for (start, end) in corners {
                var result: Selection?
                let prepared = manager.prepare(display: display, mode: mode, onEvent: { event in
                    switch event {
                    case let .completed(selection):
                        #expect(manager.window == nil)
                        result = selection
                    case .cancelled:
                        Issue.record("Valid drag was cancelled")
                    default: break
                    }
                })
                #expect(prepared)
                let window = try #require(manager.window)
                #expect(window.frame == frame)
                window.selectionView.mouseDown(with: self.makeEvent(.leftMouseDown, at: start, window: window))
                if mode == .freehand {
                    window.selectionView.mouseDragged(with: self.makeEvent(
                        .leftMouseDragged,
                        at: CGPoint(x: end.x, y: start.y),
                        window: window,
                    ))
                }
                window.selectionView.mouseDragged(with: self.makeEvent(.leftMouseDragged, at: end, window: window))
                window.selectionView.mouseUp(with: self.makeEvent(.leftMouseUp, at: end, window: window))
                #expect(result?.displayID == 42)
                #expect(result?.rect == DisplayRect(x: 100, y: 50, width: 200, height: 200))
                guard let shape = result?.shape else {
                    Issue.record("Valid drag did not produce a shape")
                    continue
                }
                switch shape {
                case .rectangle: #expect(mode == .box)
                case .freehand: #expect(mode == .freehand)
                }
            }
        }
    }

    func makeEvent(
        _ type: NSEvent.EventType,
        at point: CGPoint,
        window: NSWindow,
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1,
        ) else {
            fatalError("Failed to create mouse event")
        }

        return event
    }

    @Test(arguments: [CGFloat(1), 1.25, 1.5, 2, 3])
    func `scales corners and entire display without global origin`(scale: CGFloat) throws {
        let points = CGSize(width: 1200, height: 800)
        let pixels = try ScreenshotSizing.requestedPixelSize(forDisplayPointSize: points, pointPixelScale: scale)
        let fullDisplay = try ImageCoordinates.toPixelRect(
            from: DisplayRect(displayLocalRect: CGRect(origin: .zero, size: points)),
            displaySize: points,
            imageSize: pixels,
        )
        let bottomLeft = try ImageCoordinates.toPixelRect(
            from: DisplayRect(x: 0, y: 0, width: 100, height: 100),
            displaySize: points,
            imageSize: pixels,
        )
        let topRight = try ImageCoordinates.toPixelRect(
            from: DisplayRect(x: 1100, y: 700, width: 100, height: 100),
            displaySize: points,
            imageSize: pixels,
        )
        #expect(fullDisplay == ImagePixelRect(cgImageCropRect: CGRect(origin: .zero, size: pixels)))
        #expect(bottomLeft == ImagePixelRect(cgImageCropRect: CGRect(
            x: 0,
            y: 700 * scale,
            width: 100 * scale,
            height: 100 * scale,
        )))
        #expect(topRight == ImagePixelRect(cgImageCropRect: CGRect(
            x: 1100 * scale,
            y: 0,
            width: 100 * scale,
            height: 100 * scale,
        )))
    }

    @Test func `overlays match connected displays including menu bar`() throws {
        let manager = SelectionManager()
        defer { manager.hide() }
        for screen in NSScreen.screens {
            let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            let display = SelectionDisplay(
                id: number.uint32Value,
                frame: ScreenRect(appKitGlobalRect: screen.frame),
                visibleFrame: ScreenRect(appKitGlobalRect: screen.visibleFrame),
            )
            let prepared = manager.prepare(display: display, mode: .box, onEvent: { _ in })
            #expect(prepared)
            #expect(manager.window?.frame == screen.frame)
            #expect(manager.window?.selectionView.bounds == CGRect(origin: .zero, size: screen.frame.size))
            let pixels = try ScreenshotSizing.requestedPixelSize(
                forDisplayPointSize: screen.frame.size,
                pointPixelScale: screen.backingScaleFactor,
            )
            #expect(pixels.width == ceil(screen.frame.width * screen.backingScaleFactor))
            #expect(pixels.height == ceil(screen.frame.height * screen.backingScaleFactor))
            manager.hide()
        }
    }

    @Test func `invalid and overflowed geometry is rejected`() {
        let size = CGSize(width: 100, height: 100)
        #expect(!Selection.isValid(DisplayRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)))
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ImageCoordinates.toPixelRect(from: DisplayRect(
                x: CGFloat.greatestFiniteMagnitude,
                y: 0,
                width: CGFloat.greatestFiniteMagnitude,
                height: 10,
            ),
            displaySize: size,
            imageSize: size)
        }
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ImageCoordinates.toPixelRect(
                from: DisplayRect(x: 0, y: 0, width: 1, height: 1),
                displaySize: CGSize(width: CGFloat.leastNonzeroMagnitude, height: 1),
                imageSize: size,
            )
        }
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ScreenshotSizing.requestedPixelSize(
                forDisplayPointSize: CGSize(width: CGFloat.leastNonzeroMagnitude, height: 1),
                pointPixelScale: CGFloat.leastNonzeroMagnitude,
            )
        }
    }

    @Test func `layout change cancels overlay and discards pending capture`() async throws {
        let center = NotificationCenter()
        let service = SuspendedCaptureService()
        let manager = TestSelectionManager()
        let toolbar = TestCaptureToolbar()
        let clipboard = TestClipboardWriter()
        let display = SelectionDisplay(
            id: 1,
            frame: ScreenRect(appKitGlobalRect: layouts[0]),
            visibleFrame: ScreenRect(appKitGlobalRect: layouts[0]),
        )
        let selection = Selection(
            displayID: 1,
            rect: DisplayRect(displayLocalRect: CGRect(x: 10, y: 10, width: 100, height: 60)),
            shape: .rectangle,
        )
        let controller = CaptureController(
            modeProvider: { .box },
            saveMode: { _ in },
            clipboardService: clipboard,
            ocrService: TestTextRecognizer(),
            captureService: service,
            toolbar: toolbar,
            selectionManager: manager,
            displayProvider: { display },
            onEvent: { event in
                if case .textRecognized = event {
                    Issue.record("Stale display result was delivered")
                }
            },
        )
        let observer = DisplayConfigurationObserver(center: center) { controller.cancel() }
        controller.start()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(controller.state == .idle && !toolbar.isVisible && !manager.isVisible)
        controller.start()
        manager.onEvent?(.started)
        manager.onEvent?(.completed(selection))
        for _ in 0 ..< 100 where await !(service.started) {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(await service.started)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await service.finish(.success(TestScreenCaptureService().capture(region: selection)))
        try await Task.sleep(for: .milliseconds(20))
        #expect(controller.state == .idle && clipboard.texts.isEmpty)
        withExtendedLifetime(observer) {}
    }
}

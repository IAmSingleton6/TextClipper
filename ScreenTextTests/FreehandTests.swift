import AppKit
import Testing
@testable import ScreenText

@Suite @MainActor
struct FreehandTests {
    @Test func rejectsClicksLinesTinyPathsAndInvalidPoints() {
        #expect(SelectionGeometry.freehand(points: []) == nil)
        #expect(SelectionGeometry.freehand(points: [.zero]) == nil)
        #expect(SelectionGeometry.freehand(points: [.zero, .init(x: 50, y: 50), .init(x: 100, y: 100)]) == nil)
        #expect(SelectionGeometry.freehand(points: [.zero, .init(x: 3, y: 0), .init(x: 3, y: 3)]) == nil)
        #expect(SelectionGeometry.freehand(points: [.zero, .init(x: CGFloat.nan, y: 50), .init(x: 100, y: 100)]) == nil)
        let crossed = [CGPoint(x: 10, y: 10), .init(x: 90, y: 90), .init(x: 10, y: 90), .init(x: 90, y: 10)]
        #expect(SelectionGeometry.freehand(points: crossed) != nil)
    }

    @Test func horizontalFirstStrokeIsVisibleAndLineOnlyReleaseCancels() throws {
        let view = SelectionView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        view.mode = .freehand
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, .init(x: 10, y: 10)))
        view.mouseDragged(with: try event(.leftMouseDragged, .init(x: 90, y: 10)))
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh * 90 / 100))
        #expect(color.alphaComponent > 0.8)
        var finished = false
        view.onFinished = { #expect($0 == nil); finished = true }
        view.mouseUp(with: try event(.leftMouseUp, .init(x: 90, y: 10)))
        #expect(finished && view.selectionRect == nil)
    }

    @Test func legacyCircleDefaultMigratesToDraw() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("circle", forKey: "defaultSelectionMode")
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.lastSelectionMode == .freehand)
        settings.lastSelectionMode = .freehand
        #expect(defaults.string(forKey: "defaultSelectionMode") == "freehand")
    }

    @Test(arguments: [CGFloat(1), 1.25, 2])
    func exactCaptureMaskKeepsConcavityOrientationAndFractionalEdges(scale: CGFloat) throws {
        let width = Int(100 * scale), height = Int(80 * scale)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        let image = try #require(context.makeImage())
        let polygon = [CGPoint(x: 10.25, y: 10.25), .init(x: 70.75, y: 10.25), .init(x: 70.75, y: 30.75),
                       .init(x: 30.25, y: 30.75), .init(x: 30.25, y: 60.75), .init(x: 10.25, y: 60.75)]
        for points in [polygon, Array(polygon.reversed())] {
            let geometry = try #require(SelectionGeometry.freehand(points: points))
            let selection = Selection(displayID: 42, rect: geometry.rect, shape: geometry.shape)
            let result = try ScreenCaptureService().croppedImage(from: image, region: selection, displaySize: .init(width: 100, height: 80))
            #expect(result.width == Int(ceil(70.75 * scale) - floor(10.25 * scale)))
            #expect(result.height == Int(ceil(69.75 * scale) - floor(19.25 * scale)))
            let bitmap = NSBitmapImageRep(cgImage: result)
            func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                try #require(bitmap.colorAt(x: Int(floor(x * scale) - floor(10.25 * scale)),
                                            y: Int(floor((80 - y) * scale) - floor(19.25 * scale)))?.usingColorSpace(.deviceRGB))
            }
            let bottom = try color(50, 20)
            let top = try color(20, 50)
            let notch = try color(50, 50)
            #expect(bottom.redComponent > 0.9 && bottom.alphaComponent == 1)
            #expect(top.blueComponent > 0.9 && top.alphaComponent == 1)
            #expect(notch.alphaComponent == 0)
        }
    }

    @Test func selfCrossingMaskUsesSameEvenOddRuleAsOverlay() throws {
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let input = try #require(context.makeImage())
        let output = try ImageMasker().applyFreehandMask(to: input, points: [
            .init(x: 10, y: 10), .init(x: 90, y: 90), .init(x: 10, y: 90), .init(x: 90, y: 10)
        ])
        let bitmap = NSBitmapImageRep(cgImage: output)
        #expect(try #require(bitmap.colorAt(x: 50, y: 20)).alphaComponent == 1)
        #expect(try #require(bitmap.colorAt(x: 50, y: 80)).alphaComponent == 1)
        #expect(try #require(bitmap.colorAt(x: 20, y: 50)).alphaComponent == 0)
        let view = SelectionView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        view.mode = .freehand
        let points = [CGPoint(x: 10, y: 10), .init(x: 90, y: 90), .init(x: 10, y: 90), .init(x: 90, y: 10)]
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, points[0]))
        for point in points.dropFirst() { view.mouseDragged(with: try event(.leftMouseDragged, point)) }
        let rendered = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rendered)
        func overlayAlpha(_ x: Int, _ y: Int) throws -> CGFloat {
            try #require(rendered.colorAt(x: x * rendered.pixelsWide / 100, y: y * rendered.pixelsHigh / 100)).alphaComponent
        }
        #expect(try overlayAlpha(50, 20) == 0)
        #expect(try overlayAlpha(50, 80) == 0)
        #expect(try abs(overlayAlpha(20, 50) - 0.28) < 0.02)
    }

    @Test func nativeDrawThroughProductionMaskVisionAndPasteCopiesOnlyEnclosedText() async throws {
        let context = try #require(CGContext(data: nil, width: 900, height: 300, bitsPerComponent: 8,
                                            bytesPerRow: 3600, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 900, height: 300).fill()
        for (text, point) in [("OUTSIDE", CGPoint(x: 10, y: 270)), ("INSIDE", CGPoint(x: 350, y: 130))] {
            (text as NSString).draw(at: point, withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = try #require(context.makeImage())
        let board = NSPasteboard(name: .init("com.screentext.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        let display = SelectionDisplay(id: 42, frame: .init(x: -900, y: 900, width: 900, height: 300),
                                       visibleFrame: .init(x: -900, y: 900, width: 900, height: 300))
        let manager = SelectionManager()
        let controller = CaptureController(clipboardService: ClipboardService(pasteboard: board), ocrService: OCRService(),
            captureService: FreehandImageFixture(image: image), toolbar: TestCaptureToolbar(), selectionManager: manager,
            displayProvider: { display }, defaultModeProvider: { .freehand })
        var completed = false
        controller.onTextRecognized = {
            #expect($0 == "INSIDE")
            #expect(board.string(forType: .string) == "INSIDE")
            #expect(controller.state == .idle)
            completed = true
        }
        controller.onCaptureFailed = { _ in Issue.record("Freehand capture failed"); completed = true }
        controller.start()
        let window = try #require(manager.window)
        let points = [CGPoint(x: 0, y: 0), .init(x: 900, y: 0), .init(x: 900, y: 300),
                      .init(x: 250, y: 300), .init(x: 250, y: 200), .init(x: 0, y: 200)]
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        window.selectionView.mouseDown(with: try event(.leftMouseDown, points[0]))
        for point in points.dropFirst() { window.selectionView.mouseDragged(with: try event(.leftMouseDragged, point)) }
        window.selectionView.mouseUp(with: try event(.leftMouseUp, points.last!))
        #expect(manager.window == nil && !window.isVisible)
        #expect(controller.state == .processing)
        for _ in 0..<1500 where !completed { try await Task.sleep(for: .milliseconds(20)) }
        #expect(completed)
        let editor = NSTextView()
        editor.isRichText = false
        #expect(editor.readSelection(from: board))
        #expect(editor.string == "INSIDE")
    }
}

private struct FreehandImageFixture: ScreenCapturing {
    let image: CGImage
    func capture(region: Selection) async throws -> CGImage {
        #expect(region.displayID == 42)
        return try ScreenCaptureService().croppedImage(from: image, region: region, displaySize: .init(width: 900, height: 300))
    }
}

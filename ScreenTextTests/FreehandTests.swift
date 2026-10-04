import AppKit
@testable import ScreenText
import Testing

extension DesktopTests {
    @MainActor
    struct FreehandTests {
        @Test(arguments: [
            [DisplayPoint](), [.zero],
            [.zero, .init(x: 50, y: 50), .init(x: 100, y: 100)],
            [.zero, .init(x: 3, y: 0), .init(x: 3, y: 3)],
            [.zero, .init(x: .nan, y: 50), .init(x: 100, y: 100)],
        ])
        func `clicks lines tiny paths and nonfinite points do not form a selection`(points: [DisplayPoint]) {
            #expect(SelectionGeometry.freehand(points: points) == nil)
        }

        @Test func `a freehand triangle at the minimum area and size is accepted`() {
            #expect(SelectionGeometry.freehand(points: [.zero, .init(x: 4, y: 0), .init(x: 4, y: 4)]) != nil)
        }

        @Test func `a freehand triangle below minimum area is rejected even with valid bounds`() {
            #expect(SelectionGeometry.freehand(points: [.zero, .init(x: 4, y: 0.01), .init(x: 4, y: 4)]) == nil)
        }

        @Test func `self crossing paths can form a valid freehand selection`() {
            let points = [DisplayPoint(x: 10, y: 10), .init(x: 90, y: 90), .init(x: 10, y: 90), .init(x: 90, y: 10)]
            #expect(SelectionGeometry.freehand(points: points) != nil)
        }

        @Test(arguments: [CGFloat(1), 1.25, 2])
        func `a horizontal first stroke is visible before it encloses an area`(scale: CGFloat) throws {
            let drawing = SelectionViewFixture()

            // GIVEN
            try drawing.press(at: .init(x: 10, y: 10))

            // WHEN
            try drawing.drag(to: .init(x: 90, y: 10))

            // THEN
            let bitmap = try drawing.renderedOverlay(scale: scale)
            let x = bitmap.pixelsWide / 2
            let y = bitmap.pixelsHigh * 90 / 100
            let background = try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2))
            // A one-point stroke can straddle pixels. Compare its coverage with
            // the dimmed background instead of requiring one pixel's exact alpha.
            let radius = Int(ceil(scale))
            let strokeAlpha = try ((y - radius) ... (y + radius)).map { row in
                try #require(bitmap.colorAt(x: x, y: row)).alphaComponent
            }.max() ?? 0
            #expect(abs(background.alphaComponent - 0.28) < 0.02)
            #expect(strokeAlpha > background.alphaComponent + 0.4)
        }

        @Test func `releasing a line without enclosed area cancels and clears selection`() throws {
            let drawing = SelectionViewFixture()

            // GIVEN
            try drawing.press(at: .init(x: 10, y: 10))
            try drawing.drag(to: .init(x: 90, y: 10))

            // WHEN
            try drawing.release(at: .init(x: 90, y: 10))

            // THEN
            #expect(drawing.cancellations == 1)
            #expect(drawing.completed.isEmpty)
            #expect(drawing.view.selectionRect == nil)
        }

        @Test(arguments: [CGFloat(1), 1.25, 2], [false, true])
        func `capture masks preserve concavity orientation and fractional edges`(scale: CGFloat,
                                                                                 reversed: Bool) throws
        {
            // GIVEN
            let image = try TestImages.colored(width: Int(100 * scale), height: Int(80 * scale))
            let polygon = [DisplayPoint(x: 10.25, y: 10.25), .init(x: 70.75, y: 10.25), .init(x: 70.75, y: 30.75),
                           .init(x: 30.25, y: 30.75), .init(x: 30.25, y: 60.75), .init(x: 10.25, y: 60.75)]
            let geometry = try #require(SelectionGeometry
                .freehand(points: reversed ? Array(polygon.reversed()) : polygon))
            let selection = Selection(displayID: 42, rect: geometry.rect, shape: geometry.shape)

            // WHEN
            let result = try CaptureImageCropper().crop(
                image,
                to: selection,
                displayPointSize: .init(width: 100, height: 80),
            )

            // THEN
            #expect(result.width == Int(ceil(70.75 * scale) - floor(10.25 * scale)))
            #expect(result.height == Int(ceil(69.75 * scale) - floor(19.25 * scale)))
            let bitmap = NSBitmapImageRep(cgImage: result)
            func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                try #require(bitmap.colorAt(x: Int(floor(x * scale) - floor(10.25 * scale)),
                                            y: Int(floor((80 - y) * scale) - floor(19.25 * scale)))?
                        .usingColorSpace(.deviceRGB))
            }
            let bottom = try color(50, 20)
            let top = try color(20, 50)
            let notch = try color(50, 50)
            #expect(bottom.redComponent > 0.9)
            #expect(bottom.alphaComponent == 1)
            #expect(top.blueComponent > 0.9)
            #expect(top.alphaComponent == 1)
            #expect(notch.alphaComponent == 0)
        }

        @Test func `self crossing masks and overlays use the same even odd boundary`() throws {
            // GIVEN
            let input = try TestImages.colored(width: 100, height: 100)
            let points = [DisplayPoint(x: 10, y: 10), .init(x: 90, y: 90), .init(x: 10, y: 90), .init(x: 90, y: 10)]
            let drawing = SelectionViewFixture()

            // WHEN
            let output = try ImageMasker().applyFreehandMask(to: input, points: points.map {
                CroppedImagePixelPoint(x: $0.x, y: $0.y)
            })
            try drawing.press(at: points[0].displayLocalPoint)
            for point in points.dropFirst() {
                try drawing.drag(to: point.displayLocalPoint)
            }
            let rendered = try drawing.renderedOverlay()

            // THEN
            let bitmap = NSBitmapImageRep(cgImage: output)
            #expect(try #require(bitmap.colorAt(x: 50, y: 20)).alphaComponent == 1)
            #expect(try #require(bitmap.colorAt(x: 50, y: 80)).alphaComponent == 1)
            #expect(try #require(bitmap.colorAt(x: 20, y: 50)).alphaComponent == 0)
            func overlayAlpha(_ x: Int, _ y: Int) throws -> CGFloat {
                try #require(rendered.colorAt(x: x * rendered.pixelsWide / 100, y: y * rendered.pixelsHigh / 100))
                    .alphaComponent
            }
            #expect(try overlayAlpha(50, 20) == 0)
            #expect(try overlayAlpha(50, 80) == 0)
            #expect(try abs(overlayAlpha(20, 50) - 0.28) < 0.02)
        }

        @Test func `native freehand selection copies only enclosed text through real masking and Vision`() async throws {
            let image = try TestImages.text(["OUTSIDE", "INSIDE"],
                                            positions: [.init(x: 10, y: 270), .init(x: 350, y: 130)])
            let clipboard = PasteboardFixture()
            let selection = SelectionFixture(
                display: SelectionDisplay(id: 42, frame: .init(x: -900, y: 900, width: 900, height: 300),
                                          visibleFrame: .init(x: -900, y: 900, width: 900, height: 300)),
                initialMode: .freehand,
            )
            let capture = CaptureFixture(
                initialMode: .freehand, display: selection.display, selectionManager: selection.manager,
                captureService: FreehandImageFixture(image: image), ocrService: NativeOCRFixture().makeService(),
                clipboardService: clipboard.service,
                onEvent: { capture, event in
                    if case let .textRecognized(text) = event {
                        #expect(text == "INSIDE")
                        #expect(clipboard.board.string(forType: .string) == "INSIDE")
                        #expect(capture.isIdle)
                    }
                },
            )
            let points = [CGPoint(x: 0, y: 0), .init(x: 900, y: 0), .init(x: 900, y: 300),
                          .init(x: 250, y: 300), .init(x: 250, y: 200), .init(x: 0, y: 200)]

            // GIVEN
            capture.start()
            let window = try selection.window
            try selection.press(at: points[0])
            for point in points.dropFirst() {
                try selection.drag(to: point)
            }

            // WHEN
            try selection.release(at: #require(points.last))
            #expect(selection.manager.window == nil)
            #expect(!window.isVisible)
            #expect(capture.state == .processing)
            try await capture.waitForResult()

            // THEN
            guard case .textRecognized = try #require(capture.results.first) else {
                Issue.record("Native freehand processing should deliver recognized text")
                return
            }
            #expect(capture.isIdle)
            #expect(capture.results.count == 1)
            #expect(try clipboard.pastedText() == "INSIDE")
        }
    }
}

private struct FreehandImageFixture: ScreenCapturing {
    let image: CGImage
    func capture(region: Selection) async throws -> CGImage {
        #expect(region.displayID == 42)
        return try CaptureImageCropper().crop(self.image, to: region, displayPointSize: .init(width: 900, height: 300))
    }
}

import CoreGraphics
import Foundation
@testable import ScreenText
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ImageCoordinatesTests {
    @Test(arguments: [
        (CGSize(width: 600, height: 400), CGRect(x: 20, y: 310, width: 100, height: 60)),
        (CGSize(width: 1200, height: 800), CGRect(x: 40, y: 620, width: 200, height: 120)),
        (CGSize(width: 900, height: 1000), CGRect(x: 30, y: 775, width: 150, height: 150)),
    ])
    func `display local selections flip vertically at the actual image scale`(sizes: (CGSize, CGRect)) throws {
        // GIVEN
        let selection = DisplayRect(x: 20, y: 30, width: 100, height: 60)

        // WHEN
        let pixels = try ImageCoordinates.toPixelRect(
            from: selection, displaySize: .init(width: 600, height: 400), imageSize: sizes.0,
        )

        // THEN
        #expect(pixels == ImagePixelRect(cgImageCropRect: sizes.1))
    }

    @Test func `selections extending outside the display are clipped to its bounds`() throws {
        let size = CGSize(width: 100, height: 100)

        // WHEN
        let pixels = try ImageCoordinates.toPixelRect(
            from: .init(x: -20, y: -10, width: 140, height: 130), displaySize: size, imageSize: size,
        )

        // THEN
        #expect(pixels == ImagePixelRect(cgImageCropRect: CGRect(origin: .zero, size: size)))
    }

    @Test func `fractional selections round outward to include edge pixels`() throws {
        // WHEN
        let pixels = try ImageCoordinates.toPixelRect(
            from: .init(x: 10.25, y: 20.25, width: 30.5, height: 40.5),
            displaySize: .init(width: 100, height: 100), imageSize: .init(width: 200, height: 200),
        )

        // THEN
        #expect(pixels == ImagePixelRect(cgImageCropRect: CGRect(x: 20, y: 78, width: 62, height: 82)))
    }

    @Test(arguments: [
        DisplayRect.zero,
        .init(x: 101, y: 0, width: 10, height: 10),
        .init(x: .nan, y: 0, width: 10, height: 10),
        .init(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 10),
    ])
    func `invalid or invisible selections cannot become pixel crops`(rect: DisplayRect) {
        let size = CGSize(width: 100, height: 100)
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ImageCoordinates.toPixelRect(from: rect, displaySize: size, imageSize: size)
        }
    }

    @Test func `overflowed display to image scale is rejected`() {
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ImageCoordinates.toPixelRect(
                from: .init(x: 0, y: 0, width: 1, height: 1),
                displaySize: .init(width: CGFloat.leastNonzeroMagnitude, height: 1),
                imageSize: .init(width: 100, height: 100),
            )
        }
    }

    @Test func `mask points are relative to the bottom left of the crop`() throws {
        // GIVEN
        let displaySize = CGSize(width: 100, height: 100)
        let imageSize = CGSize(width: 200, height: 200)
        let crop = try ImageCoordinates.toPixelRect(
            from: .init(x: 10, y: 10, width: 20, height: 20), displaySize: displaySize, imageSize: imageSize,
        )

        // WHEN
        let points = try ImageCoordinates.toCroppedPoints(
            from: [.init(x: 10, y: 10), .init(x: 30, y: 30)],
            cropRect: crop, displaySize: displaySize, imageSize: imageSize,
        )

        // THEN
        #expect(points == [CroppedImagePixelPoint(x: 0, y: 0), .init(x: 40, y: 40)])
    }

    @Test func `fractional crops retain the offset of freehand points`() throws {
        // GIVEN
        let displaySize = CGSize(width: 100, height: 80)
        let imageSize = CGSize(width: 250, height: 120)
        let crop = try ImageCoordinates.toPixelRect(
            from: .init(x: 10.2, y: 20.2, width: 30.4, height: 25.6),
            displaySize: displaySize, imageSize: imageSize,
        )
        #expect(crop == ImagePixelRect(cgImageCropRect: CGRect(x: 25, y: 51, width: 77, height: 39)))

        // WHEN
        let points = try ImageCoordinates.toCroppedPoints(
            from: [.init(x: 10.2, y: 20.2), .init(x: 40.6, y: 45.8)],
            cropRect: crop, displaySize: displaySize, imageSize: imageSize,
        )

        // THEN
        try #require(points.count == 2)
        #expect(abs(points[0].x - 0.5) < 0.0001)
        #expect(abs(points[0].y - 0.3) < 0.0001)
        #expect(abs(points[1].x - 76.5) < 0.0001)
        #expect(abs(points[1].y - 38.7) < 0.0001)
    }

    @Test func `nonfinite freehand points cannot be converted to mask pixels`() {
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ImageCoordinates.toCroppedPoints(
                from: [.init(x: .nan, y: 20)], cropRect: .init(x: 25, y: 51, width: 77, height: 39),
                displaySize: .init(width: 100, height: 80), imageSize: .init(width: 250, height: 120),
            )
        }
    }

    @Test func `a bottom selection crops red pixels without mirroring to the blue top`() throws {
        // GIVEN
        let image = try TestImages.colored(width: 200, height: 200)
        let crop = try ImageCoordinates.toPixelRect(
            from: .init(x: 10, y: 10, width: 20, height: 20),
            displaySize: .init(width: 100, height: 100), imageSize: .init(width: 200, height: 200),
        )

        // WHEN
        let cropped = try #require(image.cropping(to: crop.cgImageCropRect))

        // THEN
        #expect(cropped.width == 40)
        #expect(cropped.height == 40)
        let pixels = try #require(cropped.dataProvider?.data) as Data
        try #require(pixels.count >= 4)
        #expect(pixels[0] == 255)
        #expect(pixels[2] == 0)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ScreenshotSizingTests {
    @Test(arguments: [
        (CGSize(width: 100, height: 100), CGSize(width: 125, height: 125)),
        (CGSize(width: 101, height: 61), CGSize(width: 127, height: 77)),
    ])
    func `requested pixel dimensions round upward at fractional display scale`(sizes: (CGSize, CGSize)) throws {
        #expect(try ScreenshotSizing.requestedPixelSize(forDisplayPointSize: sizes.0, pointPixelScale: 1.25) == sizes.1)
    }

    @Test(arguments: [CGFloat(0), -1, .nan, .infinity, .greatestFiniteMagnitude])
    func `invalid or overflowed pixel scale is rejected`(scale: CGFloat) {
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ScreenshotSizing.requestedPixelSize(forDisplayPointSize: .init(width: 100, height: 100),
                                                    pointPixelScale: scale)
        }
    }

    @Test func `underflowed requested pixel dimensions are rejected`() {
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ScreenshotSizing.requestedPixelSize(
                forDisplayPointSize: .init(width: CGFloat.leastNonzeroMagnitude, height: 1),
                pointPixelScale: CGFloat.leastNonzeroMagnitude,
            )
        }
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor
struct CaptureProcessingTests {
    @Test(arguments: [false, true])
    func `cancelled screen capture cannot disturb the next session`(fails: Bool) async throws {
        let service = SuspendedCaptureService()
        let clipboard = TestClipboardWriter()
        let capture = CaptureFixture(captureService: service, clipboardService: clipboard)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await service.waitUntilStarted()
        #expect(capture.state == .processing)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)

        // WHEN
        capture.toggle()
        capture.start()
        let image = try TestImages.colored()
        try await service.finish(fails ? .failure(ScreenCaptureError.captureFailed) : .success(image))
        try await capture.waitForProcessingToReturn()

        // THEN
        #expect(capture.results.isEmpty)
        #expect(clipboard.texts.isEmpty)
        #expect(clipboard.attempts.isEmpty)
        #expect(capture.state == .toolbar)
        #expect(capture.toolbarIsVisible)
        #expect(capture.selectionIsVisible)
    }

    @Test(arguments: [ScreenCaptureError.permissionDenied, .displayNotFound, .captureFailed])
    func `failed screen capture returns idle without attempting to copy`(failure: ScreenCaptureError) async throws {
        let service = SuspendedCaptureService()
        let clipboard = TestClipboardWriter()
        let capture = CaptureFixture(captureService: service, clipboardService: clipboard, onEvent: { capture, event in
            if case .failed = event {
                #expect(capture.isIdle)
            }
        })

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await service.waitUntilStarted()

        // WHEN
        try await service.finish(.failure(failure))
        try await capture.waitForResult()

        // THEN
        try #require(capture.results.count == 1)
        guard case let .failed(error) = capture.results[0] else {
            Issue.record("Screen capture failure should deliver only failure")
            return
        }
        #expect(error as? ScreenCaptureError == failure)
        #expect(capture.isIdle)
        #expect(clipboard.texts.isEmpty)
        #expect(clipboard.attempts.isEmpty)
    }
}

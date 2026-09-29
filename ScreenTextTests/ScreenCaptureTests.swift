import AppKit
import CoreGraphics
@testable import ScreenText
import Testing

struct SelectionCropCoordinatesTests {
    @Test func `flips vertical origin and uses actual image scale`() throws {
        let displaySize = CGSize(width: 600, height: 400)
        let rect = CGRect(x: 20, y: 30, width: 100, height: 60)
        let native = try SelectionCoordinates.displayRectToImagePixelRect(
            rect,
            displayPointSize: displaySize,
            imagePixelSize: displaySize,
        )
        let doubled = try SelectionCoordinates.displayRectToImagePixelRect(
            rect,
            displayPointSize: displaySize,
            imagePixelSize: .init(width: 1200, height: 800),
        )
        let uneven = try SelectionCoordinates.displayRectToImagePixelRect(
            rect,
            displayPointSize: displaySize,
            imagePixelSize: .init(width: 900, height: 1000),
        )
        #expect(native == CGRect(x: 20, y: 310, width: 100, height: 60))
        #expect(doubled == CGRect(x: 40, y: 620, width: 200, height: 120))
        #expect(uneven == CGRect(x: 30, y: 775, width: 150, height: 150))
    }

    @Test func `clips to display and rounds outward`() throws {
        let size = CGSize(width: 100, height: 100)
        let clipped = try SelectionCoordinates.displayRectToImagePixelRect(
            .init(x: -20, y: -10, width: 140, height: 130),
            displayPointSize: size,
            imagePixelSize: size,
        )
        let fractional = try SelectionCoordinates.displayRectToImagePixelRect(
            .init(x: 10.25, y: 20.25, width: 30.5, height: 40.5),
            displayPointSize: size,
            imagePixelSize: .init(width: 200, height: 200),
        )
        #expect(clipped == CGRect(origin: .zero, size: size))
        #expect(fractional == CGRect(x: 20, y: 78, width: 62, height: 82))
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try SelectionCoordinates.displayRectToImagePixelRect(
                .zero,
                displayPointSize: size,
                imagePixelSize: size,
            )
        }
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try SelectionCoordinates.displayRectToImagePixelRect(
                .init(x: 101, y: 0, width: 10, height: 10),
                displayPointSize: size,
                imagePixelSize: size,
            )
        }
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try SelectionCoordinates.displayRectToImagePixelRect(
                .init(x: CGFloat.nan, y: 0, width: 10, height: 10),
                displayPointSize: size,
                imagePixelSize: size,
            )
        }
    }

    @Test func `mask path uses coordinates inside the cropped image`() throws {
        let displaySize = CGSize(width: 100, height: 100)
        let imageSize = CGSize(width: 200, height: 200)
        let imageCropRect = try SelectionCoordinates.displayRectToImagePixelRect(
            CGRect(x: 10, y: 10, width: 20, height: 20),
            displayPointSize: displaySize,
            imagePixelSize: imageSize,
        )
        let maskPoints = try SelectionCoordinates.displayPointsToCroppedImagePoints(
            [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30)],
            imageCropRect: imageCropRect,
            displayPointSize: displaySize,
            imagePixelSize: imageSize,
        )
        #expect(maskPoints == [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 40)])
    }

    @Test func `crop reads selected pixels rather than mirrored region`() throws {
        // Data rows use the image's top-left origin: blue above, red below.
        var bytes = [UInt8](repeating: 0, count: 200 * 200 * 4)
        for y in 0 ..< 200 {
            for x in 0 ..< 200 {
                let i = (y * 200 + x) * 4
                bytes[i + (y < 100 ? 2 : 0)] = 255
                bytes[i + 3] = 255
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 800,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent,
        ))
        let imageCropRect = try SelectionCoordinates.displayRectToImagePixelRect(
            .init(x: 10, y: 10, width: 20, height: 20),
            displayPointSize: .init(width: 100, height: 100),
            imagePixelSize: .init(width: 200, height: 200),
        )
        let cropped = try #require(image.cropping(to: imageCropRect))
        #expect(cropped.width == 40 && cropped.height == 40)
        let pixels = try #require(cropped.dataProvider?.data) as Data
        #expect(pixels[0] == 255 && pixels[2] == 0)
    }
}

struct ScreenshotSizingTests {
    @Test func `rounds requested pixels up and rejects invalid scale`() throws {
        let displaySize = CGSize(width: 100, height: 100)
        #expect(try ScreenshotSizing.requestedPixelSize(forDisplayPointSize: displaySize, pointPixelScale: 1.25)
            == CGSize(width: 125, height: 125))
        #expect(throws: ScreenCaptureError.invalidRegion) {
            try ScreenshotSizing.requestedPixelSize(forDisplayPointSize: displaySize, pointPixelScale: 0)
        }
    }
}

enum TestError: Error {
    case failedToCreateContext
    case failedToCreateImage
}

struct TestScreenCaptureService: ScreenCapturing {
    func capture(region _: Selection) async throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 100,
            height: 60,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw TestError.failedToCreateContext
        }

        guard let image = context.makeImage() else {
            throw TestError.failedToCreateImage
        }

        return image
    }
}

actor SuspendedCaptureService: ScreenCapturing {
    private var continuation: CheckedContinuation<CGImage, Error>?
    private(set) var started = false
    func capture(region _: Selection) async throws -> CGImage {
        self.started = true
        return try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    func finish(_ result: Result<CGImage, Error>) {
        self.continuation?.resume(with: result); self.continuation = nil
    }
}

@MainActor
struct CaptureProcessingTests {
    @Test func `cancelling processing discards late image and protects next session`() async throws {
        let service = SuspendedCaptureService()
        let toolbar = TestCaptureToolbar()
        let manager = TestSelectionManager()
        let display = SelectionDisplay(
            id: 1,
            frame: .init(x: 0, y: 0, width: 600, height: 400),
            visibleFrame: .init(x: 0, y: 0, width: 600, height: 400),
        )
        var deliveries = 0
        let controller = CaptureController(
            clipboardService: TestClipboardWriter(),
            ocrService: TestTextRecognizer(),
            captureService: service,
            toolbar: toolbar,
            selectionManager: manager,
            displayProvider: { display },
            onEvent: { event in
                switch event {
                case .textRecognized, .failed:
                    deliveries += 1
                default: break
                }
            },
        )
        controller.start()
        manager.onEvent?(.started)
        let selection = Selection(displayID: 1, rect: .init(x: 10, y: 10, width: 100, height: 60), shape: .rectangle)
        manager.onEvent?(.completed(selection))
        #expect(controller.state == .processing)
        #expect(!toolbar.isVisible && !manager.isVisible)
        for _ in 0 ..< 100 where await !(service.started) {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await service.started)
        controller.toggle()
        controller.start()
        try await service.finish(.success(TestScreenCaptureService().capture(region: selection)))
        try await Task.sleep(for: .milliseconds(20))
        #expect(deliveries == 0)
        #expect(controller.state == .toolbar)
        controller.cancel()
    }

    @Test func `failed capture returns idle and leaves clipboard unchanged`() async throws {
        let service = SuspendedCaptureService()
        let manager = TestSelectionManager()
        let display = SelectionDisplay(
            id: 1,
            frame: .init(x: 0, y: 0, width: 600, height: 400),
            visibleFrame: .init(x: 0, y: 0, width: 600, height: 400),
        )
        var failed = false
        let changeCount = NSPasteboard.general.changeCount
        weak var observedController: CaptureController?
        let controller = CaptureController(
            clipboardService: TestClipboardWriter(),
            ocrService: TestTextRecognizer(),
            captureService: service,
            toolbar: TestCaptureToolbar(),
            selectionManager: manager,
            displayProvider: { display },
            onEvent: { event in
                if case let .failed(error) = event {
                    #expect(error as? ScreenCaptureError == .permissionDenied)
                    #expect(observedController?.state == .idle)
                    failed = true
                }
            },
        )
        observedController = controller
        controller.start()
        manager.onEvent?(.started)
        manager.onEvent?(.completed(Selection(
            displayID: 1,
            rect: .init(x: 10, y: 10, width: 100, height: 60),
            shape: .rectangle,
        )))
        for _ in 0 ..< 100 where await !(service.started) {
            try await Task.sleep(for: .milliseconds(2))
        }
        await service.finish(.failure(ScreenCaptureError.permissionDenied))
        for _ in 0 ..< 100 where !failed {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(failed)
        #expect(NSPasteboard.general.changeCount == changeCount)
    }
}

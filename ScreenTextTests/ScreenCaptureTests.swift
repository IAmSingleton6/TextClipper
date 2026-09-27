import AppKit
import CoreGraphics
@testable import ScreenText
import Testing

@MainActor
struct CaptureWindowFilterTests {
    @Test func `invalid and oversized window numbers are excluded`() {
        let numbers = [-1, 0, 42, Int(CGWindowID.max), Int(CGWindowID.max) + 1, Int.max]
        let ids = numbers.compactMap { ScreenCaptureService.capturableWindowID(for: $0) }
        #expect(ids == [42, CGWindowID.max])
    }

    @Test func `settings is capturable but capture and feedback panels are excluded`() throws {
        let settings = SettingsWindowController(settings: SettingsStore())
        let window = try #require(settings.window)
        let panels: [NSWindow] = [
            CaptureToolbarWindow(),
            SelectionWindow(displayFrame: .init(x: 0, y: 0, width: 600, height: 400)),
            CapturedTextWindow(),
            NSPanel(contentRect: .init(x: 0, y: 0, width: 100, height: 60),
                    styleMask: .borderless, backing: .buffered, defer: false),
        ]
        let ids = ScreenCaptureService.capturableWindowIDs(in: [window] + panels)
        #expect(ids == Set([CGWindowID(window.windowNumber)]))
    }
}

struct DisplayCoordinateConverterTests {
    @Test func `flips vertical origin and uses actual image scale`() throws {
        let converter = DisplayCoordinateConverter()
        let rect = CGRect(x: 20, y: 30, width: 100, height: 60)
        #expect(try converter.pixelRect(
            for: rect,
            displaySize: .init(width: 600, height: 400),
            imageSize: .init(width: 600, height: 400),
        ) == CGRect(x: 20, y: 310, width: 100, height: 60))
        #expect(try converter.pixelRect(
            for: rect,
            displaySize: .init(width: 600, height: 400),
            imageSize: .init(width: 1200, height: 800),
        ) == CGRect(x: 40, y: 620, width: 200, height: 120))
        #expect(try converter.pixelRect(
            for: rect,
            displaySize: .init(width: 600, height: 400),
            imageSize: .init(width: 900, height: 1000),
        ) == CGRect(x: 30, y: 775, width: 150, height: 150))
    }

    @Test func `clips to display and rounds outward`() throws {
        let converter = DisplayCoordinateConverter()
        let size = CGSize(width: 100, height: 100)
        #expect(try converter.pixelRect(
            for: .init(x: -20, y: -10, width: 140, height: 130),
            displaySize: size,
            imageSize: size,
        ) == CGRect(origin: .zero, size: size))
        #expect(try converter.pixelRect(
            for: .init(x: 10.25, y: 20.25, width: 30.5, height: 40.5),
            displaySize: size,
            imageSize: .init(width: 200, height: 200),
        ) == CGRect(x: 20, y: 78, width: 62, height: 82))
        #expect(throws: ScreenCaptureError.invalidRegion) { try converter.pixelRect(
            for: .zero,
            displaySize: size,
            imageSize: size,
        ) }
        #expect(throws: ScreenCaptureError.invalidRegion) { try converter.pixelRect(
            for: .init(x: 101, y: 0, width: 10, height: 10),
            displaySize: size,
            imageSize: size,
        ) }
        #expect(throws: ScreenCaptureError.invalidRegion) { try converter.pixelRect(
            for: .init(x: CGFloat.nan, y: 0, width: 10, height: 10),
            displaySize: size,
            imageSize: size,
        ) }
        #expect(throws: ScreenCaptureError.invalidRegion) { try converter.imageSize(displaySize: size, pixelScale: 0) }
        #expect(try converter.imageSize(displaySize: size, pixelScale: 2) == CGSize(width: 200, height: 200))
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
        let rect = try DisplayCoordinateConverter().pixelRect(
            for: .init(x: 10, y: 10, width: 20, height: 20),
            displaySize: .init(width: 100, height: 100),
            imageSize: .init(width: 200, height: 200),
        )
        let cropped = try #require(image.cropping(to: rect))
        #expect(cropped.width == 40 && cropped.height == 40)
        let pixels = try #require(cropped.dataProvider?.data) as Data
        #expect(pixels[0] == 255 && pixels[2] == 0)
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
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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
        let controller = CaptureController(
            clipboardService: TestClipboardWriter(),
            ocrService: TestTextRecognizer(),
            captureService: service,
            toolbar: toolbar,
            selectionManager: manager,
            displayProvider: { display },
        )
        var deliveries = 0
        controller.onEvent = { event in
            switch event {
            case .textRecognized:
                deliveries += 1
            case .failed:
                deliveries += 1
            default: break
            }
        }
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
        let controller = CaptureController(
            clipboardService: TestClipboardWriter(),
            ocrService: TestTextRecognizer(),
            captureService: service,
            toolbar: TestCaptureToolbar(),
            selectionManager: manager,
            displayProvider: { display },
        )
        var failed = false
        let changeCount = NSPasteboard.general.changeCount
        controller.onEvent = { event in
            switch event {
            case let .failed(error):
                #expect(error as? ScreenCaptureError == .permissionDenied)
                #expect(controller.state == .idle)
                failed = true
            default: break
            }
        }
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

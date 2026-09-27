import AppKit
import Testing
@testable import ScreenText

struct OCRTextProcessorTests {
    @Test func ordersRowsAndWordsWithUnequalGlyphHeights() {
        let blocks = [
            RecognizedTextBlock(text: "world", bounds: .init(x: 0.4, y: 0.8, width: 0.2, height: 0.09)),
            RecognizedTextBlock(text: "Second line.", bounds: .init(x: 0.1, y: 0.68, width: 0.6, height: 0.1)),
            RecognizedTextBlock(text: "Hello", bounds: .init(x: 0.1, y: 0.79, width: 0.2, height: 0.12)),
            RecognizedTextBlock(text: "Paragraph 2: 18%", bounds: .init(x: 0.1, y: 0.4, width: 0.6, height: 0.1))
        ]
        #expect(OCRTextProcessor().text(from: blocks) == "Hello world\nSecond line.\n\nParagraph 2: 18%")
        #expect(OCRTextProcessor().text(from: blocks.reversed()) == OCRTextProcessor().text(from: blocks))
    }

    @Test func cleanupPreservesCodeSpacingCasePunctuationAndInternalBlankLines() {
        let processor = OCRTextProcessor()
        #expect(processor.clean(" \r\nABC: 123!\r\n\r\n    let total =  42\r\nhttps://example.com?q=1\r\n ")
                == "ABC: 123!\n\n    let total =  42\nhttps://example.com?q=1")
        #expect(processor.clean(" \t\n\r ").isEmpty)
        #expect(processor.text(from: []).isEmpty)
        #expect(processor.text(from: [RecognizedTextBlock(text: " \n", bounds: .zero)]).isEmpty)
    }
}

@Suite @MainActor
struct OCRServiceTests {
    @Test(arguments: [false, true])
    func recognizesLightAndDarkTextImages(dark: Bool) async throws {
        let lines = ["Hello world", "Revenue increased by 18%.", "https://example.com"]
        let image = try renderedText(lines, dark: dark)
        let text = try await OCRService().recognizeText(from: image)
        #expect(text == lines.joined(separator: "\n"))
    }

    @Test func freehandMaskExcludesTextOutsideSelectedShape() async throws {
        let image = try renderedText(["OUTSIDE", "INSIDE"], dark: false,
                                     positions: [.init(x: 10, y: 270), .init(x: 350, y: 130)])
        let masked = try ImageMasker().applyFreehandMask(to: image, points: [
            .init(x: 0, y: 0), .init(x: 900, y: 0), .init(x: 900, y: 300),
            .init(x: 250, y: 300), .init(x: 250, y: 200), .init(x: 0, y: 200)
        ])
        #expect(try await OCRService().recognizeText(from: masked) == "INSIDE")
    }

    @Test func blankImageReturnsEmptyTextAndPreCancelledTaskThrows() async throws {
        let image = try renderedText([], dark: false)
        #expect(try await OCRService().recognizeText(from: image).isEmpty)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await OCRService().recognizeText(from: image)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled OCR must not return a result")
        } catch is CancellationError {
            // Expected; cancellation is preserved rather than turned into OCR failure.
        }
    }

    private func renderedText(_ lines: [String], dark: Bool, positions: [CGPoint]? = nil) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 900, height: 300, bitsPerComponent: 8,
                                            bytesPerRow: 3600, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (dark ? NSColor.black : NSColor.white).setFill()
        CGRect(x: 0, y: 0, width: 900, height: 300).fill()
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: positions?[index] ?? .init(x: 30, y: 220 - index * 35), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
                .foregroundColor: dark ? NSColor.white : NSColor.black
            ])
        }
        return try #require(context.makeImage())
    }
}

struct TestTextRecognizer: TextRecognizing {
    func recognizeText(from image: CGImage) async throws -> String { "Recognized fixture" }
}

actor SuspendedTextRecognizer: TextRecognizing {
    private var continuation: CheckedContinuation<String, Error>?
    private(set) var started = false
    func recognizeText(from image: CGImage) async throws -> String {
        started = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ result: Result<String, Error>) { continuation?.resume(with: result); continuation = nil }
}

@Suite @MainActor
struct OCRProcessingTests {
    @Test func cancelledOCRCannotDeliverIntoNewCaptureSession() async throws {
        let recognizer = SuspendedTextRecognizer()
        let clipboard = TestClipboardWriter()
        let manager = TestSelectionManager()
        let toolbar = TestCaptureToolbar()
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400), visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
        let controller = CaptureController(clipboardService: clipboard, ocrService: recognizer, captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: manager, displayProvider: { display })
        var deliveries = 0
        controller.onTextRecognized = { _ in deliveries += 1 }
        controller.onCaptureFailed = { _ in deliveries += 1 }
        controller.start()
        manager.onStarted?()
        manager.onCompleted?(Selection(displayID: 1, rect: .init(x: 10, y: 20, width: 100, height: 60), shape: .rectangle))
        for _ in 0..<100 where !(await recognizer.started) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await recognizer.started)
        #expect(controller.state == .processing)
        #expect(!toolbar.isVisible && !manager.isVisible)
        controller.cancel()
        controller.start()
        await recognizer.finish(.success("Late result"))
        try await Task.sleep(for: .milliseconds(20))
        #expect(deliveries == 0)
        #expect(clipboard.texts.isEmpty)
        #expect(controller.state == .toolbar)
        controller.cancel()
    }

    @Test func recognitionFailureReturnsIdleWithoutChangingClipboard() async throws {
        let recognizer = SuspendedTextRecognizer()
        let manager = TestSelectionManager()
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400), visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: recognizer, captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(), selectionManager: manager, displayProvider: { display })
        let clipboardChanges = NSPasteboard.general.changeCount
        var failed = false
        controller.onCaptureFailed = {
            #expect($0 as? OCRError == .recognitionFailed)
            #expect(controller.state == .idle)
            failed = true
        }
        controller.start()
        manager.onStarted?()
        manager.onCompleted?(Selection(displayID: 1, rect: .init(x: 10, y: 20, width: 100, height: 60), shape: .rectangle))
        for _ in 0..<100 where !(await recognizer.started) { try await Task.sleep(for: .milliseconds(2)) }
        await recognizer.finish(.failure(OCRError.recognitionFailed))
        for _ in 0..<100 where !failed { try await Task.sleep(for: .milliseconds(2)) }
        #expect(failed)
        #expect(NSPasteboard.general.changeCount == clipboardChanges)
    }
}

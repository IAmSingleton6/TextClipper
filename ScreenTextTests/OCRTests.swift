import AppKit
import os
@testable import ScreenText
import Testing
import Vision

@Suite(.timeLimit(.minutes(1)))
struct OCRTextProcessorTests {
    @Test(arguments: [false, true])
    func `text is ordered by rows and words despite unequal glyph heights`(reversed: Bool) {
        // GIVEN
        let blocks = [
            RecognizedTextBlock(text: "world", bounds: .init(x: 0.4, y: 0.8, width: 0.2, height: 0.09)),
            RecognizedTextBlock(text: "Second line.", bounds: .init(x: 0.1, y: 0.68, width: 0.6, height: 0.1)),
            RecognizedTextBlock(text: "Hello", bounds: .init(x: 0.1, y: 0.79, width: 0.2, height: 0.12)),
            RecognizedTextBlock(text: "Paragraph 2: 18%", bounds: .init(x: 0.1, y: 0.4, width: 0.6, height: 0.1)),
        ]

        // WHEN
        let text = OCRTextProcessor().text(from: reversed ? Array(blocks.reversed()) : blocks)

        // THEN
        #expect(text == "Hello world\nSecond line.\n\nParagraph 2: 18%")
    }

    @Test(arguments: ["\r\n", "\r"])
    func `cleanup preserves code spacing case punctuation and internal blank lines`(newline: String) {
        // GIVEN
        let input = [" ", "ABC: 123!", "", "    let total =  42", "https://example.com?q=1", " "]
            .joined(separator: newline)

        // WHEN
        let text = OCRTextProcessor().text(from: [RecognizedTextBlock(text: input, bounds: .zero)])

        // THEN
        #expect(text == "ABC: 123!\n\n    let total =  42\nhttps://example.com?q=1")
    }

    @Test(arguments: [" \t\n\r ", " \n"])
    func `whitespace only observations produce no text`(input: String) {
        #expect(OCRTextProcessor().text(from: [RecognizedTextBlock(text: input, bounds: .zero)]).isEmpty)
    }

    @Test func `no observations produce no text`() {
        #expect(OCRTextProcessor().text(from: []).isEmpty)
    }
}

extension DesktopTests {
    @MainActor
    struct VisionOCRTests {
        @Test func `fast recognition remains usable after cancellation`() async throws {
            let recognizer = VisionOCR(level: .fast)
            let image = try TestImages.text(["Hello world"])
            let task = Task { try await recognizer.recognizeText(from: image) }
            task.cancel()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(try await recognizer.recognizeText(from: image) == "Hello world")
        }
    }

    /// Native OCR workers initialize CoreText and WindowServer resources used by desktop tests.
    @MainActor
    struct OCRServiceTests {
        private let ocr = NativeOCRFixture()

        @Test func `launch preparation runs once and subsequent captures return their own text`() async throws {
            let preparations = OSAllocatedUnfairLock(initialState: 0)
            let service = self.ocr
                .makeService(preparer: TestOCRPreparer { [accurateRecognizer = self.ocr.accurateRecognizer] in
                    preparations.withLock { $0 += 1 }
                    try await accurateRecognizer.prepare()
                })
            let image = try TestImages.text(["Hello world"])

            // WHEN
            async let first: Void = service.prepare()
            async let second: Void = service.prepare()
            _ = await (first, second)
            let started = ContinuousClock.now
            let text = try await service.recognizeText(from: image)
            // A prepared accurate capture must not compile the models a second time.
            #expect(started.duration(to: .now) < .seconds(5))
            await service.prepare()

            // THEN
            #expect(preparations.withLock { $0 } == 1)
            #expect(text == "Hello world")
        }

        @Test func `failed preparation can retry without preventing capture`() async throws {
            let preparations = OSAllocatedUnfairLock(initialState: 0)
            let service = self.ocr
                .makeService(preparer: TestOCRPreparer { [accurateRecognizer = self.ocr.accurateRecognizer] in
                    let attempt = preparations.withLock { count in
                        count += 1
                        return count
                    }
                    if attempt == 1 {
                        throw OCRError.recognitionFailed
                    }
                    try await accurateRecognizer.prepare()
                })

            // WHEN
            await service.prepare()
            await service.prepare()
            await service.prepare()

            // THEN
            #expect(preparations.withLock { $0 } == 2)
            let image = try TestImages.text(["Hello world"])
            #expect(try await service.recognizeText(from: image) == "Hello world")
        }

        @Test func `capture arriving before launch preparation starts initialization once`() async throws {
            let preparations = OSAllocatedUnfairLock(initialState: 0)
            let service = self.ocr
                .makeService(preparer: TestOCRPreparer { [accurateRecognizer = self.ocr.accurateRecognizer] in
                    preparations.withLock { $0 += 1 }
                    try await accurateRecognizer.prepare()
                })
            let image = try TestImages.text(["Hello world"])

            // WHEN
            #expect(try await service.recognizeText(from: image) == "Hello world")
            await service.prepare()

            // THEN
            #expect(preparations.withLock { $0 } == 1)
        }

        @Test func `cancelled launch preparation leaves recognition available`() async throws {
            let service = self.ocr.makeService()
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                await service.prepare()
            }

            // WHEN
            await task.value
            await service.prepare()

            // THEN
            let image = try TestImages.text(["Hello world"])
            #expect(try await service.recognizeText(from: image) == "Hello world")
        }

        @Test(arguments: [false, true])
        func `recognizes light and dark text images`(dark: Bool) async throws {
            // GIVEN
            let lines = ["Hello world", "Revenue increased by 18%.", "https://example.com"]
            let image = try TestImages.text(lines, dark: dark)

            // WHEN
            let service = self.ocr.makeService()
            await service.prepare()
            let text = try await service.recognizeText(from: image)

            // THEN
            #expect(text == lines.joined(separator: "\n"))
        }

        @Test func `freehand masking excludes text outside the selected shape`() async throws {
            // GIVEN
            let image = try TestImages.text(["OUTSIDE", "INSIDE"],
                                            positions: [.init(x: 10, y: 270), .init(x: 350, y: 130)])
            let masked = try ImageMasker().applyFreehandMask(to: image, points: [
                .init(x: 0, y: 0), .init(x: 900, y: 0), .init(x: 900, y: 300),
                .init(x: 250, y: 300), .init(x: 250, y: 200), .init(x: 0, y: 200),
            ])

            // WHEN
            let service = self.ocr.makeService()
            await service.prepare()
            let text = try await service.recognizeText(from: masked)

            // THEN
            #expect(text == "INSIDE")
        }

        @Test func `a blank image produces no recognized text`() async throws {
            let image = try TestImages.text([])
            let service = self.ocr.makeService()
            await service.prepare()
            #expect(try await service.recognizeText(from: image).isEmpty)
        }

        @Test func `pre cancelled OCR throws cancellation instead of recognizing text`() async throws {
            // GIVEN
            let image = try TestImages.text([])
            let service = self.ocr.makeService()
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await service.recognizeText(from: image)
            }

            // WHEN / THEN
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor
struct OCRProcessingTests {
    @Test(arguments: [false, true])
    func `timed out OCR cannot write late text to the clipboard`(fails: Bool) async throws {
        let recognizer = SuspendedTextRecognizer()
        let clipboard = TestClipboardWriter()
        let capture = CaptureFixture(
            ocrService: recognizer, clipboardService: clipboard, processingTimeout: .milliseconds(50),
        )
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await recognizer.waitUntilStarted()

        try await capture.waitForResult()
        guard case let .failed(error) = try #require(capture.results.first) else {
            Issue.record("Stalled OCR should report a timeout")
            return
        }
        #expect(error as? CaptureError == .timedOut)

        capture.start()
        try await recognizer.finish(fails ? .failure(OCRError.recognitionFailed) : .success("Late result"))
        try await capture.waitForProcessingToReturn()

        #expect(capture.state == .toolbar)
        #expect(capture.results.count == 1)
        #expect(clipboard.attempts.isEmpty)
        #expect(clipboard.texts.isEmpty)
    }

    @Test(arguments: [false, true])
    func `cancelled OCR cannot deliver text or errors into a new capture session`(fails: Bool) async throws {
        let recognizer = SuspendedTextRecognizer()
        let clipboard = TestClipboardWriter()
        let capture = CaptureFixture(ocrService: recognizer, clipboardService: clipboard)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await recognizer.waitUntilStarted()
        #expect(capture.state == .processing)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)

        // WHEN
        capture.cancel()
        capture.start()
        try await recognizer.finish(fails ? .failure(OCRError.recognitionFailed) : .success("Late result"))
        try await capture.waitForProcessingToReturn()

        // THEN
        #expect(capture.results.isEmpty)
        #expect(clipboard.texts.isEmpty)
        #expect(clipboard.attempts.isEmpty)
        #expect(capture.state == .toolbar)
        #expect(capture.toolbarIsVisible)
        #expect(capture.selectionIsVisible)
    }

    @Test func `recognition failure returns idle without attempting to copy`() async throws {
        let recognizer = SuspendedTextRecognizer()
        let clipboard = TestClipboardWriter()
        let capture = CaptureFixture(ocrService: recognizer, clipboardService: clipboard, onEvent: { capture, event in
            if case .failed = event {
                #expect(capture.isIdle)
            }
        })

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await recognizer.waitUntilStarted()

        // WHEN
        try await recognizer.finish(.failure(OCRError.recognitionFailed))
        try await capture.waitForResult()

        // THEN
        try #require(capture.results.count == 1)
        guard case let .failed(error) = capture.results[0] else {
            Issue.record("Recognition failure should deliver only failure")
            return
        }
        #expect(error as? OCRError == .recognitionFailed)
        #expect(capture.isIdle)
        #expect(clipboard.texts.isEmpty)
        #expect(clipboard.attempts.isEmpty)
    }
}

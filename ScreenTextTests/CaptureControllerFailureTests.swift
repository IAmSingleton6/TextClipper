import CoreGraphics
@testable import ScreenText
import Testing

@MainActor
extension CaptureControllerTests {
    @Test func `releasing a controller cancels pending work and discards its late result`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        defer { processor.releasePendingProcessing() }
        let selection = TestSelectionManager()
        let escape = TestEscapeMonitor()
        var results = 0
        // Own the controller directly: fixture cleanup would cancel before deinit.
        var controller: CaptureController? = CaptureController(
            modeProvider: { .box }, saveMode: { _ in }, toolbar: TestCaptureToolbar(),
            selectionManager: selection, displayProvider: { testDisplay }, escapeMonitor: escape,
            processor: processor, onEvent: { event in
                switch event {
                case .textRecognized, .noTextFound, .failed: results += 1
                default: break
                }
            },
        )
        weak var releasedController = controller

        // GIVEN
        controller?.start()
        selection.beginSelection()
        selection.completeSelection()
        try await processor.waitUntilStarted()

        // WHEN
        controller = nil
        try processor.finish(with: .success(.textCopied("Late result")))
        try await processor.waitUntilReturned()

        // THEN
        #expect(releasedController == nil)
        #expect(!escape.isListening)
        #expect(processor.returnedWhileCancelled == [true])
        #expect(results == 0)
    }

    @Test func `capture retries after the toolbar becomes available`() {
        let capture = CaptureFixture(toolbarCanShow: false)

        // GIVEN
        capture.start()
        #expect(capture.events.isEmpty)
        capture.toolbar.canShow = true

        // WHEN
        capture.start()

        // THEN
        #expect(capture.state == .toolbar)
        #expect(capture.toolbarIsVisible)
        #expect(capture.selectionIsVisible)
        #expect(capture.activityChanges == [true])
    }

    @Test func `the toolbar cursor exclusion is applied when capture starts`() {
        let exclusion = ScreenRect(x: 10, y: 20, width: 260, height: 50)
        let capture = CaptureFixture(toolbarCursorExclusionRect: exclusion)

        // WHEN
        capture.start()

        // THEN
        #expect(capture.selections.cursorExclusionRect == exclusion)
    }

    @Test func `beginning selection clears the hidden toolbar cursor exclusion`() {
        let capture = CaptureFixture(toolbarCursorExclusionRect: .init(x: 10, y: 20, width: 260, height: 50))

        // GIVEN
        capture.start()

        // WHEN
        capture.beginSelection()

        // THEN
        #expect(capture.selections.cursorExclusionRect == nil)
        #expect(!capture.toolbarIsVisible)
    }

    @Test func `repeated completion while processing does not process another selection`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        let retainedCallback = try #require(capture.selections.onEvent)
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()

        // WHEN
        retainedCallback(.completed(boxSelection))

        // THEN
        #expect(processor.selections == [boxSelection])
        #expect(capture.state == .processing)
        #expect(capture.results.isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor
struct CaptureProcessorTests {
    @Test func `capture failure prevents recognition and clipboard writes`() async {
        let capture = RecordingCaptureService(failure: .permissionDenied)
        let recognizer = RecordingTextRecognizer()
        let clipboard = TestClipboardWriter()
        let processor = CaptureProcessor(captureService: capture, ocrService: recognizer, clipboardService: clipboard)

        // WHEN
        await #expect(throws: ScreenCaptureError.permissionDenied) { try await processor.process(boxSelection) }

        // THEN
        #expect(await capture.calls == 1)
        #expect(await recognizer.calls == 0)
        #expect(clipboard.attempts.isEmpty)
    }

    @Test func `recognition failure prevents clipboard writes`() async {
        let capture = RecordingCaptureService()
        let recognizer = RecordingTextRecognizer(failure: .recognitionFailed)
        let clipboard = TestClipboardWriter()
        let processor = CaptureProcessor(captureService: capture, ocrService: recognizer, clipboardService: clipboard)

        // WHEN
        await #expect(throws: OCRError.recognitionFailed) { try await processor.process(boxSelection) }

        // THEN
        #expect(await capture.calls == 1)
        #expect(await recognizer.calls == 1)
        #expect(clipboard.attempts.isEmpty)
    }

    @Test func `pre cancelled processing never captures recognizes or copies`() async {
        let capture = RecordingCaptureService()
        let recognizer = RecordingTextRecognizer()
        let clipboard = TestClipboardWriter()
        let processor = CaptureProcessor(captureService: capture, ocrService: recognizer, clipboardService: clipboard)

        // GIVEN
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await processor.process(boxSelection)
        }

        // WHEN
        await #expect(throws: CancellationError.self) { try await task.value }

        // THEN
        #expect(await capture.calls == 0)
        #expect(await recognizer.calls == 0)
        #expect(clipboard.attempts.isEmpty)
    }
}

private actor RecordingCaptureService: ScreenCapturing {
    private(set) var calls = 0
    private let failure: ScreenCaptureError?
    init(failure: ScreenCaptureError? = nil) {
        self.failure = failure
    }

    func capture(region _: Selection) async throws -> CGImage {
        self.calls += 1
        if let failure = self.failure {
            throw failure
        }
        return try TestImages.colored()
    }
}

private actor RecordingTextRecognizer: TextRecognizing {
    private(set) var calls = 0
    private let failure: OCRError?
    init(failure: OCRError? = nil) {
        self.failure = failure
    }

    func recognizeText(from _: CGImage) async throws -> String {
        self.calls += 1
        if let failure = self.failure {
            throw failure
        }
        return "Recorded text"
    }
}

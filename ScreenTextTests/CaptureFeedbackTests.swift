import AppKit
@testable import ScreenText
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor
struct CaptureFeedbackTests {
    @Test(arguments: [false, true])
    func `slow capture feedback appears after a delay even when previews are disabled`(
        showCapturedText: Bool,
    ) async throws {
        let feedback = try FeedbackFixture(showCapturedText: showCapturedText)

        // GIVEN
        feedback.beginCapture()

        // WHEN
        feedback.processingChanged(true)
        #expect(feedback.notifications.message == nil)
        try await feedback.notifications.waitUntilShown()

        // THEN
        #expect(feedback.notifications.message == "Reading text… Press Escape to cancel")
        #expect(feedback.notifications.display?.id == testDisplay.id)
        #expect(feedback.notifications.dismissAfter == nil)
        #expect(feedback.popup.text == nil)
    }

    @Test(arguments: [PendingCaptureOutcome.text, .noText, .failure, .cancelled])
    private func `pending feedback clears when processing ends`(outcome: PendingCaptureOutcome) async throws {
        let feedback = try FeedbackFixture()
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor, onEvent: { _, event in
            switch event {
            case let .started(display): feedback.beginCapture(on: display)
            case let .processingChanged(processing): feedback.processingChanged(processing)
            case let .textRecognized(text): feedback.copiedText(text)
            case .noTextFound: feedback.noTextFound()
            case let .failed(error): feedback.fail(error)
            case .activityChanged: break
            }
        })

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()
        try await feedback.notifications.waitUntilShown()
        #expect(feedback.notifications.message == "Reading text… Press Escape to cancel")
        capture.toggle()
        #expect(feedback.notifications.message == "Reading text… Press Escape to cancel")

        // WHEN
        if outcome == .cancelled {
            capture.triggerEscape()
        }
        try processor.finish(with: outcome.result)
        try await capture.waitForProcessingToReturn()

        // THEN
        #expect(capture.isIdle)
        #expect(feedback.notifications.message == outcome.message)
        #expect(feedback.popup.text == (outcome == .text ? "Hello" : nil))
    }

    @Test(arguments: [PendingCaptureOutcome.text, .noText, .failure, .cancelled])
    private func `quick captures never show processing feedback`(outcome: PendingCaptureOutcome) async throws {
        let feedback = try FeedbackFixture()
        feedback.beginCapture()
        feedback.processingChanged(true)

        feedback.processingChanged(false)
        switch outcome {
        case .text: feedback.copiedText("Hello")
        case .noText: feedback.noTextFound()
        case .failure: feedback.fail(OCRError.recognitionFailed)
        case .cancelled: break
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(feedback.notifications.messages == outcome.message.map { [$0] } ?? [])
        #expect(feedback.notifications.message == outcome.message)
        #expect(feedback.popup.text == (outcome == .text ? "Hello" : nil))
    }

    @Test(arguments: [false, true])
    func `hiding feedback or starting a new capture cancels the pending message`(startsNewCapture: Bool) async throws {
        let feedback = try FeedbackFixture()
        feedback.beginCapture()
        feedback.processingChanged(true)

        if startsNewCapture {
            feedback.beginCapture(on: SelectionDisplay(
                id: 7, frame: testDisplay.frame, visibleFrame: testDisplay.visibleFrame,
            ))
        } else {
            feedback.hide()
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(feedback.notifications.messages.isEmpty)
        #expect(feedback.notifications.message == nil)
        #expect(feedback.popup.text == nil)
    }

    @Test func `timed out captures replace processing feedback and allow another capture`() async throws {
        let feedback = try FeedbackFixture(processingFeedbackDelay: .zero)
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor, processingTimeout: .milliseconds(100), onEvent: { _, event in
            switch event {
            case let .started(display): feedback.beginCapture(on: display)
            case let .processingChanged(processing): feedback.processingChanged(processing)
            case let .failed(error): feedback.fail(error)
            default: break
            }
        })
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await feedback.notifications.waitUntilShown()
        #expect(feedback.notifications.message == "Reading text… Press Escape to cancel")

        try await capture.waitForResult()
        #expect(capture.isIdle)
        #expect(!capture.escape.isListening)
        #expect(feedback.notifications.message == "Text recognition timed out. Try again.")
        #expect(feedback.notifications.dismissAfter == .seconds(3))

        capture.start()
        try processor.finish(with: .success(.textCopied("Late text")))
        try await capture.waitForProcessingToReturn()
        #expect(capture.state == .toolbar)
        #expect(capture.results.count == 1)
        #expect(feedback.notifications.message == nil)
        #expect(feedback.popup.text == nil)
    }

    @Test func `copied text is suppressed when previews are disabled`() throws {
        let feedback = try FeedbackFixture(showCapturedText: false)

        // GIVEN
        feedback.beginCapture()

        // WHEN
        feedback.copiedText("Hello")

        // THEN
        #expect(feedback.popup.text == nil)
    }

    @Test func `copied text appears on the capture display when previews are enabled`() throws {
        let feedback = try FeedbackFixture()

        // GIVEN
        feedback.beginCapture()

        // WHEN
        feedback.copiedText("Hello")

        // THEN
        #expect(feedback.popup.text == "Hello")
        #expect(feedback.popup.display?.id == testDisplay.id)
    }

    @Test func `enabling previews applies to subsequent copied text`() throws {
        let feedback = try FeedbackFixture(showCapturedText: false)

        // GIVEN
        feedback.beginCapture()
        feedback.copiedText("Hidden")
        feedback.storage.settings.showCapturedText = true

        // WHEN
        feedback.copiedText("Hello")

        // THEN
        #expect(feedback.popup.text == "Hello")
    }

    @Test func `no text found replaces the preview with a notification on the capture display`() throws {
        let feedback = try FeedbackFixture()

        // GIVEN
        feedback.beginCapture()
        feedback.copiedText("Previous text")

        // WHEN
        feedback.noTextFound()

        // THEN
        #expect(feedback.popup.text == nil)
        #expect(feedback.notifications.message == "No text found")
        #expect(feedback.notifications.display?.id == testDisplay.id)
    }

    @Test(arguments: [
        (FeedbackFailure.clipboard, "Could not copy text to the clipboard"),
        (.ocr, "Could not read selected text"),
        (.timeout, "Text recognition timed out. Try again."),
        (.missingDisplay, "Display is no longer available"),
        (.capture, "Could not capture selection"),
        (.invalidRegion, "Could not capture selection"),
        (.unknown, "Could not capture selection"),
    ])
    private func `routine failures clear previews and show a specific message`(failure: (
        FeedbackFailure,
        String,
    )) throws {
        let feedback = try FeedbackFixture()

        // GIVEN
        feedback.beginCapture()
        feedback.copiedText("Previous text")

        // WHEN
        feedback.fail(failure.0.error)

        // THEN
        #expect(feedback.popup.text == nil)
        #expect(feedback.notifications.message == failure.1)
        #expect(feedback.notifications.display?.id == testDisplay.id)
        #expect(feedback.permissionRequests == 0)
    }

    @Test func `permission denial clears feedback and requests permission guidance`() throws {
        let feedback = try FeedbackFixture()

        // GIVEN
        feedback.beginCapture()
        feedback.noTextFound()
        feedback.copiedText("Previous text")

        // WHEN
        feedback.fail(ScreenCaptureError.permissionDenied)

        // THEN
        #expect(feedback.permissionRequests == 1)
        #expect(feedback.popup.text == nil)
        #expect(feedback.notifications.message == nil)
    }

    @Test func `a new capture clears old feedback and uses the new display`() throws {
        let feedback = try FeedbackFixture()
        let nextDisplay = SelectionDisplay(id: 7, frame: .init(x: 0, y: 0, width: 600, height: 400),
                                           visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))

        // GIVEN
        feedback.beginCapture()
        feedback.noTextFound()
        feedback.copiedText("Previous text")

        // WHEN
        feedback.beginCapture(on: nextDisplay)

        // THEN
        #expect(feedback.popup.text == nil)
        #expect(feedback.notifications.message == nil)
        feedback.copiedText("New text")
        #expect(feedback.popup.display?.id == nextDisplay.id)
    }

    @Test func `blank copied text clears the previous preview`() throws {
        let feedback = try FeedbackFixture()

        // GIVEN
        feedback.beginCapture()
        feedback.copiedText("Previous text")

        // WHEN
        feedback.copiedText(" \n")

        // THEN
        #expect(feedback.popup.text == nil)
    }

    @Test func `copied text without a capture display does not open a preview`() throws {
        let feedback = try FeedbackFixture()

        // WHEN
        feedback.copiedText("Hello")

        // THEN
        #expect(feedback.popup.text == nil)
    }

    @Test func `hiding feedback clears both preview and notification`() throws {
        let feedback = try FeedbackFixture()

        // GIVEN
        feedback.beginCapture()
        feedback.noTextFound()
        feedback.copiedText("Hello")

        // WHEN
        feedback.hide()

        // THEN
        #expect(feedback.popup.text == nil)
        #expect(feedback.notifications.message == nil)
    }

    @Test func `empty OCR notifies after idle and preserves the native clipboard`() async throws {
        let clipboard = PasteboardFixture()
        clipboard.board.setString("Keep this", forType: .string)
        let changes = clipboard.board.changeCount
        let feedback = try FeedbackFixture()
        let capture = CaptureFixture(
            ocrService: FixedTextRecognizer(text: " \n"), clipboardService: clipboard.service,
            onEvent: { capture, event in
                switch event {
                case let .started(display): feedback.beginCapture(on: display)
                case .noTextFound:
                    #expect(capture.isIdle)
                    #expect(clipboard.board.changeCount == changes)
                    feedback.noTextFound()
                default: break
                }
            },
        )

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.completeSelection()
        try await capture.waitForResult()

        // THEN
        #expect(feedback.notifications.message == "No text found")
        #expect(feedback.notifications.display?.id == testDisplay.id)
        #expect(clipboard.board.string(forType: .string) == "Keep this")
        #expect(clipboard.board.changeCount == changes)
        #expect(capture.isIdle)
    }
}

extension DesktopTests {
    @MainActor
    struct CapturedTextWindowTests {
        @Test func `native preview is bounded and leaves focus and clipboard unchanged`() {
            let popup = CapturedTextWindow()
            defer { popup.hide() }
            let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let clipboard = NSPasteboard.general.changeCount

            // WHEN
            popup.show(String(repeating: "Long preview text. ", count: 1000), on: testDisplay)

            // THEN
            #expect(popup.isVisible)
            #expect(!popup.canBecomeKey)
            #expect(!popup.canBecomeMain)
            #expect(popup.ignoresMouseEvents)
            #expect(popup.frame.width == 320)
            #expect(popup.frame.height > 32 && popup.frame.height < 150)
            #expect(abs(popup.frame.midX - testDisplay.visibleFrame.midX) < 1)
            #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
            #expect(NSPasteboard.general.changeCount == clipboard)
        }

        @Test func `hiding a preview releases its text view`() {
            let popup = CapturedTextWindow()
            defer { popup.hide() }

            // GIVEN
            popup.show("Hello", on: testDisplay)

            // WHEN
            popup.hide()

            // THEN
            #expect(!popup.isVisible)
            #expect(popup.contentView == nil)
        }

        @Test func `blank text does not open a native preview`() {
            let popup = CapturedTextWindow()
            defer { popup.hide() }
            popup.show(" \n", on: testDisplay)
            #expect(!popup.isVisible)
        }
    }
}

@MainActor
private final class FeedbackFixture {
    let storage: SettingsFixture
    let popup = TestTextPopup()
    let notifications = TestNotifications()
    private(set) var permissionRequests = 0
    private let processingFeedbackDelay: Duration
    private lazy var controller = CaptureFeedbackController(
        settings: self.storage.settings, popup: self.popup, notifications: self.notifications,
        processingFeedbackDelay: self.processingFeedbackDelay,
        onPermissionRequired: { [weak self] in self?.permissionRequests += 1 },
    )

    init(showCapturedText: Bool = true, processingFeedbackDelay: Duration = .milliseconds(50)) throws {
        self.storage = try SettingsFixture()
        self.storage.settings.showCapturedText = showCapturedText
        self.processingFeedbackDelay = processingFeedbackDelay
    }

    func beginCapture(on display: SelectionDisplay = testDisplay) {
        self.controller.beginCapture(on: display)
    }

    func processingChanged(_ isProcessing: Bool) {
        self.controller.onProcessingChanged(isProcessing)
    }

    func copiedText(_ text: String) {
        self.controller.onCopiedText(text)
    }

    func noTextFound() {
        self.controller.onNoTextFound()
    }

    func fail(_ error: Error) {
        self.controller.onFailed(error)
    }

    func hide() {
        self.controller.hide()
    }
}

@MainActor
private final class TestTextPopup: CapturedTextPresenting {
    var text: String?
    var display: SelectionDisplay?
    func show(_ text: String, on display: SelectionDisplay) {
        self.text = text
        self.display = display
    }

    func hide() {
        self.text = nil
    }
}

@MainActor
private final class TestNotifications: NotificationPresenting {
    var message: String?
    var display: SelectionDisplay?
    var dismissAfter: Duration?
    private(set) var messages: [String] = []
    private let shown = TestSignal()
    func show(_ message: String, on display: SelectionDisplay?, dismissAfter: Duration?) {
        self.message = message
        self.display = display
        self.dismissAfter = dismissAfter
        self.messages.append(message)
        self.shown.signal()
    }

    func hide() {
        self.message = nil
    }

    func waitUntilShown() async throws {
        try await self.shown.wait(for: "capture notification to appear")
    }
}

private enum FeedbackFailure {
    case clipboard, ocr, timeout, missingDisplay, capture, invalidRegion, unknown
    enum Unknown: Error { case failure }
    var error: Error {
        switch self {
        case .clipboard: ClipboardError.writeFailed
        case .ocr: OCRError.recognitionFailed
        case .timeout: CaptureError.timedOut
        case .missingDisplay: ScreenCaptureError.displayNotFound
        case .capture: ScreenCaptureError.captureFailed
        case .invalidRegion: ScreenCaptureError.invalidRegion
        case .unknown: Unknown.failure
        }
    }
}

private enum PendingCaptureOutcome {
    case text, noText, failure, cancelled

    var result: Result<CaptureProcessingResult, Error> {
        switch self {
        case .text, .cancelled: .success(.textCopied("Hello"))
        case .noText: .success(.noTextFound)
        case .failure: .failure(OCRError.recognitionFailed)
        }
    }

    var message: String? {
        switch self {
        case .text, .cancelled: nil
        case .noText: "No text found"
        case .failure: "Could not read selected text"
        }
    }
}

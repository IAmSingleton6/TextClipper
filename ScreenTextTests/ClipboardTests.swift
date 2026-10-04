import AppKit
@testable import ScreenText
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor
struct ClipboardServiceTests {
    @Test func `copied text preserves formatting when pasted into a native text view`() throws {
        let clipboard = PasteboardFixture()
        let text = "Hello world\n\nRevenue: 18%!\n    let total =  42\nhttps://example.com"

        // GIVEN
        clipboard.board.setString("Old clipboard", forType: .string)

        // WHEN
        let copied = try clipboard.service.copy(text)

        // THEN
        #expect(copied)
        #expect(clipboard.board.string(forType: .string) == text)
        #expect(try clipboard.pastedText() == text)
    }

    @Test(arguments: ["", " \t\r\n"])
    func `empty text preserves every existing clipboard type`(text: String) throws {
        let clipboard = PasteboardFixture()
        let customType = NSPasteboard.PasteboardType("com.screentext.test-data")
        let data = Data([1, 2, 3])

        // GIVEN
        clipboard.board.setString("Keep this", forType: .string)
        clipboard.board.setData(data, forType: customType)
        let changeCount = clipboard.board.changeCount

        // WHEN
        let copied = try clipboard.service.copy(text)

        // THEN
        #expect(!copied)
        #expect(clipboard.board.changeCount == changeCount)
        #expect(clipboard.board.string(forType: .string) == "Keep this")
        #expect(clipboard.board.data(forType: customType) == data)
    }

    @Test func `a rejected pasteboard write reports write failure`() {
        let board = FailingPasteboard()
        let service = ClipboardService(pasteboard: board)

        // WHEN
        #expect(throws: ClipboardError.writeFailed) { try service.copy("Text") }

        // THEN
        #expect(board.cleared)
        #expect(board.attemptedType == .string)
    }
}

extension DesktopTests {
    @MainActor
    struct ClipboardProcessingTests {
        @Test func `native box selection recognizes text that can be pasted`() async throws {
            let clipboard = PasteboardFixture()
            print("[ClipboardProcessingTests] Rendering OCR text fixture")
            let image = try TestImages.text(["Hello world", "Total: 42"])
            let selection = SelectionFixture(display: SelectionDisplay(
                id: 99, frame: .init(x: -600, y: 400, width: 600, height: 400),
                visibleFrame: .init(x: -600, y: 400, width: 600, height: 400),
            ))
            let capture = CaptureFixture(
                display: selection.display,
                selectionManager: selection.manager,
                captureService: ImageCaptureFixture(image: image),
                ocrService: NativeOCRFixture().makeService(),
                clipboardService: clipboard.service,
            )

            // GIVEN
            print("[ClipboardProcessingTests] Presenting native selection")
            capture.start()
            try selection.press(at: .init(x: 300, y: 200))
            #expect(!capture.toolbarIsVisible)

            // WHEN
            print("[ClipboardProcessingTests] Completing native selection")
            try selection.release(at: .init(x: 100, y: 50))
            #expect(selection.manager.window == nil)
            #expect(capture.state == .processing)
            capture.toggle()
            capture.toggle()
            #expect(capture.state == .processing)
            print("[ClipboardProcessingTests] Waiting for OCR and clipboard completion")
            // First-use captures must finish while accurate OCR prepares elsewhere.
            try await capture.waitForResult()

            // THEN
            guard case let .textRecognized(text) = try #require(capture.results.first) else {
                Issue.record("Native box processing should deliver recognized text")
                return
            }
            #expect(capture.isIdle)
            #expect(capture.results.count == 1)
            #expect(text.contains("Hello world"))
            #expect(text.contains("42"))
            #expect(try clipboard.pastedText() == text)
        }

        @Test func `recognized text is copied before completion is delivered`() async throws {
            let clipboard = TestClipboardWriter()
            let capture = CaptureFixture(
                ocrService: FixedTextRecognizer(text: "Hello\nworld"),
                clipboardService: clipboard,
                onEvent: { capture, event in
                    if case let .textRecognized(text) = event {
                        #expect(text == "Hello\nworld")
                        #expect(clipboard.texts == ["Hello\nworld"])
                        #expect(capture.isIdle)
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
            try #require(capture.results.count == 1)
            guard case .textRecognized = capture.results[0] else {
                Issue.record("Successful copying should deliver recognized text")
                return
            }
            #expect(clipboard.texts == ["Hello\nworld"])
            #expect(capture.isIdle)
        }

        @Test func `empty OCR reports no text found without copying`() async throws {
            let clipboard = TestClipboardWriter()
            let capture = CaptureFixture(
                ocrService: FixedTextRecognizer(text: " \t\n"), clipboardService: clipboard,
            )

            // GIVEN
            capture.start()
            capture.beginSelection()

            // WHEN
            capture.completeSelection()
            try await capture.waitForResult()

            // THEN
            try #require(capture.results.count == 1)
            guard case .noTextFound = capture.results[0] else {
                Issue.record("Empty OCR should report no text found, without success or failure")
                return
            }
            #expect(capture.isIdle)
            #expect(clipboard.texts.isEmpty)
        }

        @Test func `a failed clipboard write returns idle and reports failure without success`() async throws {
            let clipboard = TestClipboardWriter(fails: true)
            let capture = CaptureFixture(
                ocrService: FixedTextRecognizer(text: "Hello"), clipboardService: clipboard,
                onEvent: { capture, event in
                    if case .failed = event {
                        #expect(capture.isIdle)
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
            try #require(capture.results.count == 1)
            guard case let .failed(error) = capture.results[0] else {
                Issue.record("A rejected clipboard write should deliver only failure")
                return
            }
            #expect(error as? ClipboardError == .writeFailed)
            #expect(clipboard.texts.isEmpty)
            #expect(clipboard.attempts == ["Hello"])
            #expect(capture.isIdle)
        }
    }
}

@MainActor
private final class FailingPasteboard: TextPasteboard {
    var cleared = false
    var attemptedType: NSPasteboard.PasteboardType?

    func clearContents() -> Int {
        self.cleared = true
        return 1
    }

    func setString(_: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        self.attemptedType = type
        return false
    }
}

private struct ImageCaptureFixture: ScreenCapturing {
    let image: CGImage
    func capture(region: Selection) async throws -> CGImage {
        #expect(region.displayID == 99)
        #expect(region.rect == DisplayRect(x: 100, y: 50, width: 200, height: 150))
        #expect(region.shape == .rectangle)
        print("[ClipboardProcessingTests] Capture fixture returned the image for Vision OCR")
        return self.image
    }
}

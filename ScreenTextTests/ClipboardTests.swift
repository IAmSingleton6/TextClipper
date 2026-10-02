import AppKit
@testable import ScreenText
import Testing

@MainActor
struct ClipboardServiceTests {
    @Test func `writes exact text and native text view can paste it`() throws {
        let board = NSPasteboard(name: .init("com.screentext.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("Old clipboard", forType: .string)
        let text = "Hello world\n\nRevenue: 18%!\n    let total =  42\nhttps://example.com"
        #expect(try ClipboardService(pasteboard: board).copy(text))
        #expect(board.string(forType: .string) == text)
        let editor = NSTextView(frame: .init(x: 0, y: 0, width: 600, height: 400))
        editor.isRichText = false
        #expect(editor.readSelection(from: board))
        #expect(editor.string == text)
    }

    @Test func `empty results preserve all existing clipboard types`() throws {
        let board = NSPasteboard(name: .init("com.screentext.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("Keep this", forType: .string)
        let customType = NSPasteboard.PasteboardType("com.screentext.test-data")
        let data = Data([1, 2, 3])
        board.setData(data, forType: customType)
        let changeCount = board.changeCount
        let service = ClipboardService(pasteboard: board)
        #expect(try !service.copy(""))
        #expect(try !service.copy(" \t\r\n"))
        #expect(board.changeCount == changeCount)
        #expect(board.string(forType: .string) == "Keep this")
        #expect(board.data(forType: customType) == data)
    }

    @Test func `failed native write throws meaningful error`() {
        let board = FailingPasteboard()
        #expect(throws: ClipboardError.writeFailed) { try ClipboardService(pasteboard: board).copy("Text") }
        #expect(board.cleared)
        #expect(board.attemptedType == .string)
    }
}

@MainActor
final class FailingPasteboard: TextPasteboard {
    var cleared = false
    var attemptedType: NSPasteboard.PasteboardType?
    func clearContents() -> Int {
        self.cleared = true; return 1
    }

    func setString(_: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        self.attemptedType = type
        return false
    }
}

@MainActor
final class TestClipboardWriter: ClipboardWriting {
    var texts: [String] = []
    var fails = false
    func copy(_ text: String) throws -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if self.fails {
            throw ClipboardError.writeFailed
        }
        self.texts.append(text)
        return true
    }
}

struct FixedTextRecognizer: TextRecognizing {
    let text: String
    func recognizeText(from _: CGImage) async throws -> String {
        self.text
    }
}

@MainActor
struct ClipboardProcessingTests {
    @Test func `native selection vision and paste produce expected text`() async throws {
        let context = try #require(CGContext(data: nil, width: 900, height: 300, bitsPerComponent: 8,
                                             bytesPerRow: 3600, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 900, height: 300).fill()
        for (index, line) in ["Hello world", "Total: 42"].enumerated() {
            (line as NSString).draw(at: .init(x: 30, y: 220 - index * 35), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
                .foregroundColor: NSColor.black,
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = try #require(context.makeImage())
        let board = NSPasteboard(name: .init("com.screentext.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        let manager = SelectionManager()
        defer { manager.hide() }
        let display = SelectionDisplay(id: 99, frame: .init(x: -600, y: 400, width: 600, height: 400),
                                       visibleFrame: .init(x: -600, y: 400, width: 600, height: 400))
        let toolbar = TestCaptureToolbar()
        let controller = CaptureController(clipboardService: ClipboardService(pasteboard: board),
                                           ocrService: OCRService(), captureService: ImageCaptureFixture(image: image),
                                           toolbar: toolbar, selectionManager: manager, displayProvider: { display })
        var finished = false
        var copied = false
        controller.onEvent = { event in
            switch event {
            case .textRecognized:
                finished = true; copied = true
            case .failed:
                Issue.record("Selection-to-paste pipeline failed"); finished = true
            default: break
            }
        }
        controller.start()
        let window = try #require(manager.window)
        window.selectionView.mouseDown(
            with: makeEvent(.leftMouseDown, at: .init(x: 300, y: 200), window: window)
        )
        #expect(!toolbar.isVisible)
        window.selectionView.mouseUp(
            with: makeEvent(.leftMouseUp, at: .init(x: 100, y: 50), window: window)
        )
        #expect(manager.window == nil)
        #expect(controller.state == .processing)
        for _ in 0 ..< 1500 where !finished {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(copied)
        #expect(controller.state == .idle)
        let editor = NSTextView(frame: .init(x: 0, y: 0, width: 600, height: 400))
        editor.isRichText = false
        #expect(editor.readSelection(from: board))
        #expect(editor.string == "Hello world\nTotal: 42")
    }
    
    func makeEvent(
        _ type: NSEvent.EventType,
        at point: CGPoint,
        window: NSWindow
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event")
        }

        return event
    }

    @Test func `success copies before completion and returns idle`() async throws {
        let clipboard = TestClipboardWriter()
        let manager = TestSelectionManager()
        let controller = controller(clipboard: clipboard, text: "Hello\nworld", manager: manager)
        var completed = false
        controller.onEvent = { event in
            switch event {
            case let .textRecognized(text):
                #expect(text == "Hello\nworld")
                #expect(clipboard.texts == ["Hello\nworld"])
                #expect(controller.state == .idle)
                completed = true
            default: break
            }
        }
        self.startSelection(controller, manager: manager)
        for _ in 0 ..< 100 where !completed {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(completed)
    }

    @Test func `empty result returns idle without copy or success callback`() async throws {
        let clipboard = TestClipboardWriter()
        let manager = TestSelectionManager()
        let controller = controller(clipboard: clipboard, text: " \t\n", manager: manager)
        controller.onEvent = { event in
            switch event {
            case .textRecognized:
                Issue.record("Empty OCR must not report copy success")
            default: break
            }
        }
        self.startSelection(controller, manager: manager)
        for _ in 0 ..< 100 where controller.isActive {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(controller.state == .idle)
        #expect(clipboard.texts.isEmpty)
    }

    @Test func `write failure returns idle and reports error without success`() async throws {
        let clipboard = TestClipboardWriter()
        clipboard.fails = true
        let manager = TestSelectionManager()
        let controller = controller(clipboard: clipboard, text: "Hello", manager: manager)
        var failed = false
        controller.onEvent = { event in
            switch event {
            case .textRecognized:
                Issue.record("Failed write must not report success")
            case let .failed(error):
                #expect(error as? ClipboardError == .writeFailed)
                #expect(controller.state == .idle)
                failed = true
            default: break
            }
        }
        self.startSelection(controller, manager: manager)
        for _ in 0 ..< 100 where !failed {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(failed)
        #expect(clipboard.texts.isEmpty)
    }

    private func controller(clipboard: TestClipboardWriter, text: String,
                            manager: TestSelectionManager) -> CaptureController
    {
        CaptureController(clipboardService: clipboard, ocrService: FixedTextRecognizer(text: text),
                          captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(),
                          selectionManager: manager, displayProvider: {
                              SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400),
                                               visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
                          })
    }

    private func startSelection(_ controller: CaptureController, manager: TestSelectionManager) {
        controller.start()
        manager.onEvent?(.started)
        manager.onEvent?(.completed(Selection(
            displayID: 1,
            rect: .init(x: 10, y: 20, width: 100, height: 60),
            shape: .rectangle,
        )))
    }
}

struct ImageCaptureFixture: ScreenCapturing {
    let image: CGImage
    func capture(region: Selection) async throws -> CGImage {
        #expect(region.displayID == 99)
        #expect(region.rect == CGRect(x: 100, y: 50, width: 200, height: 150))
        #expect(region.shape == .rectangle)
        return self.image
    }
}

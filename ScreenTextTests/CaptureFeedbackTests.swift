import AppKit
@testable import ScreenText
import Testing

@MainActor
struct CaptureFeedbackTests {
    private let display = SelectionDisplay(id: 7, frame: CGRect(x: -1440, y: 900, width: 1440, height: 900),
                                           visibleFrame: CGRect(x: -1440, y: 900, width: 1440, height: 875))

    @Test func `preference defaults on and persists without captured text`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(persistence: SettingsPersistence(defaults: defaults))
        #expect(settings.showCapturedText)
        settings.showCapturedText = false
        #expect(!SettingsStore(persistence: SettingsPersistence(defaults: defaults)).showCapturedText)
        #expect(defaults.persistentDomain(forName: name)?.count == 1)
    }

    @Test func `feedback uses capture display and separates permission from routine errors`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(persistence: SettingsPersistence(defaults: defaults))
        settings.showCapturedText = false
        let popup = TestTextPopup()
        let notifications = TestNotifications()
        var permissionRequests = 0
        let feedback = CaptureFeedbackController(
            settings: settings,
            popup: popup,
            notifications: notifications,
            onPermissionRequired: { permissionRequests += 1 },
        )
        feedback.beginCapture(on: self.display)
        feedback.copiedText("Hello")
        #expect(popup.text == nil)
        settings.showCapturedText = true
        feedback.copiedText("Hello")
        #expect(popup.text == "Hello")
        #expect(popup.display?.id == self.display.id)
        feedback.noTextFound()
        #expect(popup.text == nil)
        #expect(notifications.message == "No text found")
        #expect(notifications.display?.id == self.display.id)
        feedback.failed(ClipboardError.writeFailed)
        #expect(notifications.message == "Could not copy text to the clipboard")
        feedback.failed(OCRError.recognitionFailed)
        #expect(notifications.message == "Could not read selected text")
        feedback.failed(ScreenCaptureError.displayNotFound)
        #expect(notifications.message == "Display is no longer available")
        feedback.failed(ScreenCaptureError.permissionDenied)
        #expect(permissionRequests == 1)
        #expect(notifications.message == nil)
        feedback.copiedText("Previous capture")
        feedback.beginCapture(on: self.display)
        #expect(popup.text == nil)
        feedback.copiedText(" \n")
        #expect(popup.text == nil)
    }

    @Test func `empty pipeline notifies after idle and preserves native clipboard`() async throws {
        let board = NSPasteboard(name: .init("com.screentext.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("Keep this", forType: .string)
        let count = board.changeCount
        let manager = TestSelectionManager()
        var notified = false
        weak var observedController: CaptureController?
        let controller = CaptureController(clipboardService: ClipboardService(pasteboard: board),
                                           ocrService: FixedTextRecognizer(text: " \n"),
                                           captureService: TestScreenCaptureService(),
                                           toolbar: TestCaptureToolbar(), selectionManager: manager,
                                           displayProvider: { self.display },
                                           onEvent: { event in
                                               if case .noTextFound = event {
                                                   #expect(observedController?.state == .idle)
                                                   #expect(board.changeCount == count)
                                                   notified = true
                                               }
                                           })
        observedController = controller
        controller.start()
        manager.onEvent?(.started)
        manager.onEvent?(.completed(Selection(
            displayID: self.display.id,
            rect: CGRect(x: 10, y: 20, width: 100, height: 60),
            shape: .rectangle,
        )))
        for _ in 0 ..< 100 where !notified {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(notified)
        #expect(board.string(forType: .string) == "Keep this")
    }

    @Test func `native preview is bounded nonactivating and releases text`() {
        let popup = CapturedTextWindow()
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let clipboard = NSPasteboard.general.changeCount
        popup.show(String(repeating: "Long preview text. ", count: 1000), on: self.display)
        #expect(popup.isVisible)
        #expect(!popup.canBecomeKey && !popup.canBecomeMain && popup.ignoresMouseEvents)
        #expect(popup.frame.width == 320)
        #expect(popup.frame.height > 32 && popup.frame.height < 150)
        #expect(abs(popup.frame.midX - self.display.visibleFrame.midX) < 1)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
        #expect(NSPasteboard.general.changeCount == clipboard)
        popup.hide()
        #expect(!popup.isVisible && popup.contentView == nil)
        popup.show(" \n", on: self.display)
        #expect(!popup.isVisible)
    }
}

@MainActor private final class TestTextPopup: CapturedTextPresenting {
    var text: String?
    var display: SelectionDisplay?
    func show(_ text: String, on display: SelectionDisplay) {
        self.text = text; self.display = display
    }

    func hide() {
        self.text = nil
    }
}

@MainActor private final class TestNotifications: NotificationPresenting {
    var message: String?
    var display: SelectionDisplay?
    func show(_ message: String, on display: SelectionDisplay?) {
        self.message = message; self.display = display
    }

    func hide() {
        self.message = nil
    }
}

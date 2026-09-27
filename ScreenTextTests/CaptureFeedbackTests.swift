import AppKit
import Testing
@testable import ScreenText

@Suite @MainActor
struct CaptureFeedbackTests {
    private let display = SelectionDisplay(id: 7, frame: CGRect(x: -1440, y: 900, width: 1440, height: 900),
                                          visibleFrame: CGRect(x: -1440, y: 900, width: 1440, height: 875))

    @Test func preferenceDefaultsOffAndPersistsWithoutCapturedText() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.showCapturedText)
        settings.showCapturedText = true
        #expect(SettingsStore(defaults: defaults).showCapturedText)
        #expect(defaults.persistentDomain(forName: name)?.count == 1)
    }

    @Test func feedbackUsesCaptureDisplayAndSeparatesPermissionFromRoutineErrors() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let popup = TestTextPopup()
        let notifications = TestNotifications()
        var permissionRequests = 0
        let feedback = CaptureFeedbackController(settings: settings, popup: popup, notifications: notifications,
                                                 permissionRequired: { permissionRequests += 1 })
        feedback.beginCapture(on: display)
        feedback.copiedText("Hello")
        #expect(popup.text == nil)
        settings.showCapturedText = true
        feedback.copiedText("Hello")
        #expect(popup.text == "Hello")
        #expect(popup.display?.id == display.id)
        feedback.noTextFound()
        #expect(popup.text == nil)
        #expect(notifications.message == "No text found")
        #expect(notifications.display?.id == display.id)
        feedback.failed(ClipboardError.writeFailed)
        #expect(notifications.message == "Could not copy text to the clipboard")
        feedback.failed(OCRError.recognitionFailed)
        #expect(notifications.message == "Could not read selected text")
        feedback.failed(ScreenCaptureError.displayNotFound)
        #expect(notifications.message == "Could not capture selection")
        feedback.failed(ScreenCaptureError.permissionDenied)
        #expect(permissionRequests == 1)
        #expect(notifications.message == nil)
        feedback.copiedText("Previous capture")
        feedback.beginCapture(on: display)
        #expect(popup.text == nil)
        feedback.copiedText(" \n")
        #expect(popup.text == nil)
    }

    @Test func emptyPipelineNotifiesAfterIdleAndPreservesNativeClipboard() async throws {
        let board = NSPasteboard(name: .init("com.screentext.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("Keep this", forType: .string)
        let count = board.changeCount
        let manager = TestSelectionManager()
        let controller = CaptureController(clipboardService: ClipboardService(pasteboard: board),
            ocrService: FixedTextRecognizer(text: " \n"), captureService: TestScreenCaptureService(),
            toolbar: TestCaptureToolbar(), selectionManager: manager, displayProvider: { display })
        var notified = false
        controller.onNoTextFound = {
            #expect(controller.state == .idle)
            #expect(board.changeCount == count)
            notified = true
        }
        controller.start()
        manager.onStarted?()
        manager.onCompleted?(Selection(displayID: display.id, rect: CGRect(x: 10, y: 20, width: 100, height: 60), shape: .rectangle))
        for _ in 0..<100 where !notified { try await Task.sleep(for: .milliseconds(2)) }
        #expect(notified)
        #expect(board.string(forType: .string) == "Keep this")
    }

    @Test func nativePreviewIsBoundedNonactivatingAndReleasesText() {
        let popup = CapturedTextWindow()
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let clipboard = NSPasteboard.general.changeCount
        popup.show(String(repeating: "Long preview text. ", count: 1000), on: display)
        #expect(popup.isVisible)
        #expect(!popup.canBecomeKey && !popup.canBecomeMain && popup.ignoresMouseEvents)
        #expect(popup.frame.width == 320)
        #expect(popup.frame.height > 32 && popup.frame.height < 150)
        #expect(abs(popup.frame.midX - display.visibleFrame.midX) < 1)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
        #expect(NSPasteboard.general.changeCount == clipboard)
        popup.hide()
        #expect(!popup.isVisible && popup.contentView == nil)
        popup.show(" \n", on: display)
        #expect(!popup.isVisible)
    }
}

@MainActor private final class TestTextPopup: CapturedTextPresenting {
    var text: String?
    var display: SelectionDisplay?
    func show(_ text: String, on display: SelectionDisplay) { self.text = text; self.display = display }
    func hide() { text = nil }
}

@MainActor private final class TestNotifications: NotificationPresenting {
    var message: String?
    var display: SelectionDisplay?
    func show(_ message: String, on display: SelectionDisplay?) { self.message = message; self.display = display }
    func hide() { message = nil }
}

import Foundation

@MainActor
final class CaptureFeedbackController {
    private let settings: SettingsStore
    private let popup: any CapturedTextPresenting
    private let notifications: any NotificationPresenting
    private let permissionRequired: () -> Void
    private var display: SelectionDisplay?

    init(settings: SettingsStore = SettingsStore(),
         popup: any CapturedTextPresenting = CapturedTextWindow(),
         notifications: any NotificationPresenting = NotificationService(),
         permissionRequired: @escaping () -> Void) {
        self.settings = settings
        self.popup = popup
        self.notifications = notifications
        self.permissionRequired = permissionRequired
    }

    func beginCapture(on display: SelectionDisplay) {
        hide()
        self.display = display
    }

    // Called only after the clipboard write has succeeded.
    func copiedText(_ text: String) {
        guard settings.showCapturedText, let display,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            popup.hide()
            return
        }
        popup.show(text, on: display)
    }

    func noTextFound() {
        popup.hide()
        notifications.show("No text found", on: display)
    }

    func failed(_ error: Error) {
        hide()
        if error as? ScreenCaptureError == .permissionDenied {
            permissionRequired()
            return
        }
        let message: String
        switch error {
        case is ClipboardError: message = "Could not copy text to the clipboard"
        case is OCRError: message = "Could not read selected text"
        default: message = "Could not capture selection"
        }
        notifications.show(message, on: display)
    }

    func hide() {
        popup.hide()
        notifications.hide()
    }
}

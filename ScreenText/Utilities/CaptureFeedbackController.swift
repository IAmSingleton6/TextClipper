import Foundation

@MainActor
final class CaptureFeedbackController {
    private let settings: SettingsStore
    private let popup: any CapturedTextPresenting
    private let notifications: any NotificationPresenting
    private let onPermissionRequired: () -> Void
    private var display: SelectionDisplay?

    init(settings: SettingsStore = SettingsStore(persistence: SettingsPersistence(defaults: .standard)),
         popup: any CapturedTextPresenting = CapturedTextWindow(),
         notifications: any NotificationPresenting = NotificationService(),
         onPermissionRequired: @escaping () -> Void)
    {
        self.settings = settings
        self.popup = popup
        self.notifications = notifications
        self.onPermissionRequired = onPermissionRequired
    }

    func beginCapture(on display: SelectionDisplay) {
        self.hide()
        self.display = display
    }

    /// Called only after the clipboard write has succeeded.
    func copiedText(_ text: String) {
        guard self.settings.showCapturedText, let display,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            self.popup.hide()
            return
        }
        self.popup.show(text, on: display)
    }

    func noTextFound() {
        self.popup.hide()
        self.notifications.show("No text found", on: self.display)
    }

    func failed(_ error: Error) {
        self.hide()
        if error as? ScreenCaptureError == .permissionDenied {
            self.onPermissionRequired()
            return
        }
        let message = switch error {
        case is ClipboardError: "Could not copy text to the clipboard"
        case is OCRError: "Could not read selected text"
        case ScreenCaptureError.displayNotFound: "Display is no longer available"
        default: "Could not capture selection"
        }
        self.notifications.show(message, on: self.display)
    }

    func hide() {
        self.popup.hide()
        self.notifications.hide()
    }
}

import Foundation

@MainActor
final class CaptureFeedbackController {
    private let settings: SettingsStore
    private let popup: any CapturedTextPresenting
    private let notifications: any NotificationPresenting
    private let onPermissionRequired: () -> Void
    private var display: SelectionDisplay?

    init(
        settings: SettingsStore = SettingsStore(persistence: SettingsPersistence(defaults: .standard)),
        popup: any CapturedTextPresenting = CapturedTextWindow(),
        notifications: any NotificationPresenting = NotificationService(),
        onPermissionRequired: @escaping () -> Void,
    ) {
        self.settings = settings
        self.popup = popup
        self.notifications = notifications
        self.onPermissionRequired = onPermissionRequired
    }

    func beginCapture(on display: SelectionDisplay) {
        self.hide()
        self.display = display
    }

    func onProcessingChanged(_ isProcessing: Bool) {
        if isProcessing {
            self.notifications.show("Reading text… Press Escape to cancel", on: self.display, dismissAfter: nil)
        } else {
            self.notifications.hide()
        }
    }

    func onCopiedText(_ text: String) {
        guard
            self.settings.showCapturedText,
            let display,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            self.popup.hide()
            return
        }

        self.popup.show(text, on: display)
    }

    func onNoTextFound() {
        self.popup.hide()
        self.notifications.show("No text found", on: self.display)
    }

    func onFailed(_ error: Error) {
        self.hide()

        if error as? ScreenCaptureError == .permissionDenied {
            self.onPermissionRequired()
            return
        }

        let message = self.errorMessage(for: error)
        self.notifications.show(message, on: self.display)
    }

    private func errorMessage(for error: Error) -> String {
        switch error {
        case is ClipboardError:
            "Could not copy text to the clipboard"
        case is OCRError:
            "Could not read selected text"
        case ScreenCaptureError.displayNotFound:
            "Display is no longer available"
        default:
            "Could not capture selection"
        }
    }

    func hide() {
        self.popup.hide()
        self.notifications.hide()
    }
}

import AppKit

@MainActor
final class PermissionManager {
    func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        if error as? ScreenCaptureError == .permissionDenied {
            alert.messageText = "Screen Recording permission required"
            alert.informativeText = "ScreenText needs Screen Recording permission to read text from your screen. Enable it in System Settings, then try capturing again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.messageText = error is OCRError ? "Could not read selected text" : "Could not capture selection"
            alert.informativeText = "Please try selecting the text again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

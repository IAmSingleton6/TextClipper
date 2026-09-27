import AppKit

@MainActor
final class PermissionManager {
    func showPermissionRequired() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = "ScreenText needs Screen Recording permission to read text from your screen. Enable it in System Settings, then try capturing again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}

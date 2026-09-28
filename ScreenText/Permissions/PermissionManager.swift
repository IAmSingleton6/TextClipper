import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class PermissionManager {
    private let checkAccess: () -> Bool
    private let requestAccess: () -> Bool
    private let openSettings: () -> Void
    private(set) var hasScreenRecordingAccess: Bool

    init(
        checkAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        openSettings: @escaping () -> Void = {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        },
    ) {
        self.checkAccess = checkAccess
        self.requestAccess = requestAccess
        self.openSettings = openSettings
        self.hasScreenRecordingAccess = checkAccess()
    }

    func refresh() {
        self.hasScreenRecordingAccess = self.checkAccess()
    }

    func enableScreenRecording() {
        // Register the permission request before opening Settings so the app appears there.
        let granted = self.requestAccess()
        self.refresh()
        if !granted, !self.hasScreenRecordingAccess {
            self.openScreenRecordingSettings()
        }
    }

    func openScreenRecordingSettings() {
        self.openSettings()
    }

    func showPermissionRequired() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = "ScreenText needs Screen Recording permission to read text from your screen. Enable it in System Settings, then try capturing again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            self.openScreenRecordingSettings()
        }
    }
}

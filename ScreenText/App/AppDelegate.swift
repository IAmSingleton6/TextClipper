import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionManager = PermissionManager()
    private lazy var feedbackController = CaptureFeedbackController(permissionRequired: { [weak self] in
        self?.permissionManager.showPermissionRequired()
    })
    private let captureController = CaptureController()
    private var shortcutManager: GlobalShortcutManager?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        captureController.onCaptureStarted = { [weak self] display in
            self?.feedbackController.beginCapture(on: display)
        }
        captureController.onNoTextFound = { [weak self] in
            self?.feedbackController.noTextFound()
        }
        captureController.onTextRecognized = { [weak self] text in
            self?.feedbackController.copiedText(text)
        }
        captureController.onCaptureFailed = { [weak self] error in
            self?.feedbackController.failed(error)
        }
        let onCapture: () -> Void = { [weak self] in
            self?.captureController.toggle()
        }
        let menuBarController = MenuBarController(onCapture: onCapture)
        self.menuBarController = menuBarController
        captureController.onActivityChanged = { [weak menuBarController] isActive in
            menuBarController?.setCaptureActive(isActive)
        }
        let shortcutManager = GlobalShortcutManager(onCapture: onCapture)
        self.shortcutManager = shortcutManager
        shortcutManager.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutManager?.stop()
        shortcutManager = nil
        captureController.cancel()
        feedbackController.hide()
        menuBarController = nil
    }
}

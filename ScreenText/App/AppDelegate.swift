import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureController = CaptureController()
    private var shortcutManager: GlobalShortcutManager?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        menuBarController = nil
    }
}

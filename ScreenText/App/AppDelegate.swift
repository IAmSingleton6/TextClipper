import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private let permissionManager = PermissionManager()
    private lazy var feedbackController = CaptureFeedbackController(settings: settings, permissionRequired: { [weak self] in
        self?.permissionManager.showPermissionRequired()
    })
    private lazy var captureController = CaptureController(defaultModeProvider: { [weak self] in self?.settings.defaultMode ?? .box })
    private var displayObserver: DisplayConfigurationObserver?
    private var shortcutManager: GlobalShortcutManager?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        displayObserver = DisplayConfigurationObserver { [weak self] in
            // An overlay and its local coordinates belong to one display layout.
            self?.captureController.cancel()
            self?.feedbackController.hide()
        }
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
        let menuBarController = MenuBarController(onCapture: onCapture, onSettings: { [weak self] in
            self?.captureController.cancel()
            self?.feedbackController.hide()
            self?.settingsWindow.show()
        })
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
        displayObserver = nil
        shortcutManager?.stop()
        shortcutManager = nil
        captureController.cancel()
        feedbackController.hide()
        menuBarController = nil
    }
}

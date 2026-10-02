import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let permissionManager = PermissionManager()

    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        permissions: permissionManager,
    )

    private lazy var feedbackController = CaptureFeedbackController(
        settings: settings,
        // TODO: Not sure whether the name is asking whether it is required, or to show the required
        permissionRequired: { [weak self] in
            self?.permissionManager.showPermissionRequired()
        },
    )

    private lazy var captureController = CaptureController(
        savedModeProvider: { [weak self] in
            self?.settings.lastSelectionMode ?? .box
        },
        saveMode: { [weak self] mode in
            self?.settings.lastSelectionMode = mode
        },
    )

    private var displayObserver: DisplayConfigurationObserver?
    private var shortcutManager: GlobalShortcutManager?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        self.displayObserver = DisplayConfigurationObserver { [weak self] in
            self?.captureController.cancel()
            self?.feedbackController.hide()
        }

        self.menuBarController = MenuBarController { [weak self] action in
            guard let self else { return }
            switch action {
            case .capture:
                self.captureController.toggle()
            case .settings:
                self.captureController.cancel()
                self.feedbackController.hide()
                self.settingsWindow.show()
            }
        }

        self.captureController.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case let .started(display):
                self.feedbackController.beginCapture(on: display)
            case let .activityChanged(isActive):
                self.menuBarController?.setCaptureActive(isActive)
            case .noTextFound:
                self.feedbackController.noTextFound()
            case let .textRecognized(text):
                self.feedbackController.copiedText(text)
            case let .failed(error):
                self.feedbackController.failed(error)
            }
        }

        self.shortcutManager = GlobalShortcutManager { [weak self] in
            self?.captureController.toggle()
        }
        self.shortcutManager?.start()

        if self.settings.consumeFirstLaunch() {
            self.settingsWindow.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_: Notification) {
        self.shortcutManager?.stop()
        self.captureController.cancel()
        self.feedbackController.hide()
    }
}

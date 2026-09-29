import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore(persistence: SettingsPersistence(defaults: .standard))
    private let permissionManager = PermissionManager()

    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        permissions: permissionManager,
    )

    private lazy var feedbackController = CaptureFeedbackController(
        settings: settings,
        onPermissionRequired: { [weak self] in
            self?.permissionManager.showPermissionRequired()
        },
    )

    private lazy var captureController = CaptureController(
        savedModeProvider: { [weak self] in
            self?.settings.lastSelectionMode ?? .box
        },
        saveMode: { [weak self] mode in
            self?.settings.selectCaptureMode(mode)
        },
        onEvent: { [weak self] event in
            self?.handleCaptureEvent(event)
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
                self.settingsWindowController.show()
            }
        }

        self.shortcutManager = GlobalShortcutManager(
            source: KeyboardShortcutSource(name: AppShortcuts.captureText),
        ) { [weak self] in
            self?.captureController.toggle()
        }
        self.shortcutManager?.start()

        if self.settings.consumeFirstLaunch() {
            self.settingsWindowController.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    private func handleCaptureEvent(_ event: CaptureEvent) {
        switch event {
        case let .started(display):
            self.feedbackController.beginCapture(on: display)
        case let .activityChanged(isActive):
            self.menuBarController?.setCaptureActive(isActive)
        case .noTextFound:
            self.feedbackController.onNoTextFound()
        case let .textRecognized(text):
            self.feedbackController.onCopiedText(text)
        case let .failed(error):
            self.feedbackController.onFailed(error)
        }
    }

    func applicationWillTerminate(_: Notification) {
        self.shortcutManager?.stop()
        self.captureController.cancel()
        self.feedbackController.hide()
    }
}

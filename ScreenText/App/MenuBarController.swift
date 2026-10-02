import AppKit
import KeyboardShortcuts

enum MenuBarAction {
    case capture
    case settings
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem

    private let onAction: (MenuBarAction) -> Void
    private var captureItem: NSMenuItem?

    init(onAction: @escaping (MenuBarAction) -> Void) {
        self.onAction = onAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        self.configureButton()
        self.configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "ScreenText")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "ScreenText"
        button.setAccessibilityLabel("ScreenText")
    }

    private func configureMenu() {
        let menu = NSMenu(title: "ScreenText")
        menu.autoenablesItems = false
        menu.delegate = self

        let captureItem = NSMenuItem(title: "Capture Text", action: #selector(captureText), keyEquivalent: "")
        captureItem.target = self
        captureItem.setShortcut(for: AppShortcuts.captureText)
        self.captureItem = captureItem
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ScreenText", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    func setCaptureActive(_ isActive: Bool) {
        self.captureItem?.state = isActive ? .on : .off
    }

    func menuWillOpen(_: NSMenu) {
        // AppKit handles the menu key equivalent while tracking; avoid a second global invocation.
        KeyboardShortcuts.disable(AppShortcuts.captureText)
    }

    func menuDidClose(_: NSMenu) {
        KeyboardShortcuts.enable(AppShortcuts.captureText)
    }

    @objc private func captureText() {
        self.onAction(.capture)
    }

    @objc private func showSettings() {
        // Let status-menu tracking finish before activating the Settings window.
        DispatchQueue.main.async { [weak self] in
            self?.onAction(.settings)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

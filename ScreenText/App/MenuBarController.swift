import AppKit
import KeyboardShortcuts

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem

    private let onCapture: () -> Void
    private var captureItem: NSMenuItem?

    init(onCapture: @escaping () -> Void) {
        self.onCapture = onCapture
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        configureMenu()
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
        captureItem.setShortcut(for: .captureText)
        self.captureItem = captureItem
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: "")
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ScreenText", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func setCaptureActive(_ isActive: Bool) {
        captureItem?.state = isActive ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        // AppKit handles the menu key equivalent while tracking; avoid a second global invocation.
        KeyboardShortcuts.disable(.captureText)
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(.captureText)
    }

    @objc private func captureText() {
        onCapture()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

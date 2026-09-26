import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem

    override init() {
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

        // These entry points become available when their implementation phases land.
        let captureItem = NSMenuItem(title: "Capture Text", action: nil, keyEquivalent: "")
        captureItem.isEnabled = false
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

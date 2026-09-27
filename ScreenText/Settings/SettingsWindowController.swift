import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let login: LoginItemController

    init(settings: SettingsStore, login: LoginItemController = LoginItemController()) {
        self.login = login
        let host = NSHostingView(rootView: SettingsView(settings: settings, login: login))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ScreenText Settings"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        login.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

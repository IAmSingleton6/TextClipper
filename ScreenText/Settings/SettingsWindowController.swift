import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let login: LoginItemController

    init(settings: SettingsStore, login: LoginItemController = LoginItemController(),
         permissions: PermissionManager = PermissionManager())
    {
        self.login = login
        let host = NSHostingView(rootView: SettingsView(settings: settings, login: login, permissions: permissions))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ScreenText Settings"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        self.login.refresh()
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }
}

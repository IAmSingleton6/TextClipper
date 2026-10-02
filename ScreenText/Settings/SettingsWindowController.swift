import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let login: LoginItemController
    private let permissions: PermissionManager

    init(
        settings: SettingsStore,
        permissions: PermissionManager = PermissionManager(),
        login: LoginItemController = LoginItemController(),
    ) {
        self.login = login
        self.permissions = permissions

        let host = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                login: login,
                permissions: permissions,
            ),
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false,
        )
        window.title = "ScreenText Settings"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: NSApp,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        self.refreshExternalStatuses()
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window.orderFrontRegardless()
    }

    @objc private func applicationDidBecomeActive(_: Notification) {
        guard self.window?.isVisible == true else { return }
        self.refreshExternalStatuses()
    }

    private func refreshExternalStatuses() {
        self.login.refresh()
        self.permissions.refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

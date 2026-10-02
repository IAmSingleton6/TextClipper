import AppKit
import KeyboardShortcuts
@testable import ScreenText
import ServiceManagement
import Testing

@MainActor
struct SettingsTests {
    @Test func `initial setup is offered only once across launches`() throws {
        let storage = try SettingsFixture()
        #expect(storage.settings.consumeFirstLaunch())
        #expect(!storage.settings.consumeFirstLaunch())
        #expect(!storage.restoredSettings().consumeFirstLaunch())
    }

    @Test func `disabling previews persists only the preference without captured text`() throws {
        let storage = try SettingsFixture()

        // WHEN
        storage.settings.showCapturedText = false

        // THEN
        #expect(!storage.restoredSettings().showCapturedText)
        #expect(storage.storedKeys == ["showCapturedText"])
    }

    @Test func `new preferences default to box mode and captured text previews`() throws {
        let storage = try SettingsFixture()
        #expect(storage.settings.lastSelectionMode == .box)
        #expect(storage.settings.showCapturedText)
    }

    @Test func `changed preferences survive a new settings store`() throws {
        let storage = try SettingsFixture()

        // WHEN
        storage.settings.selectCaptureMode(.freehand)
        storage.settings.showCapturedText = false

        // THEN
        let restored = storage.restoredSettings()
        #expect(restored.lastSelectionMode == .freehand)
        #expect(!restored.showCapturedText)
        #expect(storage.storedKeys == ["lastSelectionMode", "showCapturedText"])
    }

    @Test(arguments: ["unknown", "circle"])
    func `unsupported stored modes fall back to box and can be replaced`(rawMode: String) throws {
        let storage = try SettingsFixture(storedMode: rawMode)

        // GIVEN
        #expect(storage.settings.lastSelectionMode == .box)

        // WHEN
        storage.settings.selectCaptureMode(.freehand)

        // THEN
        #expect(storage.defaults.string(forKey: "lastSelectionMode") == "freehand")
        #expect(storage.restoredSettings().lastSelectionMode == .freehand)
    }

    @Test(arguments: [CaptureMode.freehand, .box])
    func `capture modes load and save their explicit raw storage values`(mode: CaptureMode) throws {
        let storage = try SettingsFixture(storedMode: mode.rawValue)
        let newMode: CaptureMode = mode == .box ? .freehand : .box

        // GIVEN
        #expect(storage.settings.lastSelectionMode == mode)

        // WHEN
        storage.settings.selectCaptureMode(newMode)

        // THEN
        #expect(storage.settings.lastSelectionMode == newMode)
        #expect(storage.defaults.string(forKey: "lastSelectionMode") == newMode.rawValue)
        #expect(storage.restoredSettings().lastSelectionMode == newMode)
    }
}

@MainActor
struct PermissionManagerTests {
    @Test func `initial permission status does not request access`() {
        let permission = PermissionFixture()
        #expect(!permission.manager.hasScreenRecordingAccess)
        #expect(permission.requests == 0)
        #expect(permission.settingsOpens == 0)
    }

    @Test func `a denied permission request opens screen recording settings`() {
        let permission = PermissionFixture()

        // WHEN
        permission.manager.enableScreenRecording()

        // THEN
        #expect(!permission.manager.hasScreenRecordingAccess)
        #expect(permission.requests == 1)
        #expect(permission.settingsOpens == 1)
    }

    @Test func `a granted permission request refreshes access without opening settings`() {
        let permission = PermissionFixture(requestGrantsAccess: true)

        // GIVEN
        #expect(!permission.manager.hasScreenRecordingAccess)

        // WHEN
        permission.manager.enableScreenRecording()

        // THEN
        #expect(permission.manager.hasScreenRecordingAccess)
        #expect(permission.requests == 1)
        #expect(permission.settingsOpens == 0)
    }

    @Test func `refresh follows externally granted and revoked permission`() {
        let permission = PermissionFixture()

        // GIVEN
        #expect(!permission.manager.hasScreenRecordingAccess)
        permission.allowed = true
        permission.manager.refresh()
        #expect(permission.manager.hasScreenRecordingAccess)
        permission.manager.enableScreenRecording()
        #expect(permission.requests == 1)
        #expect(permission.settingsOpens == 0)

        // WHEN
        permission.allowed = false
        permission.manager.refresh()

        // THEN
        #expect(!permission.manager.hasScreenRecordingAccess)
    }
}

@MainActor
struct LoginItemControllerTests {
    @Test func `launch at login is not enabled automatically`() {
        let service = TestLoginItem()
        let login = LoginItemController(service: service)
        #expect(!login.isEnabled)
        #expect(service.registerCount == 0)
    }

    @Test func `registration awaiting approval is shown as enabled`() {
        let service = TestLoginItem(nextStatus: .requiresApproval)
        let login = LoginItemController(service: service)

        // WHEN
        login.isEnabled = true

        // THEN
        #expect(login.isEnabled)
        #expect(login.status == .requiresApproval)
        #expect(service.registerCount == 1)
    }

    @Test func `refresh reflects approval granted outside the app`() {
        let service = TestLoginItem(status: .requiresApproval)
        let login = LoginItemController(service: service)

        // WHEN
        service.status = .enabled
        login.refresh()

        // THEN
        #expect(login.status == .enabled)
        #expect(login.isEnabled)
    }

    @Test func `failed unregister preserves actual enabled status and reports an error`() {
        let service = TestLoginItem(status: .enabled, fails: true)
        let login = LoginItemController(service: service)

        // WHEN
        login.setEnabled(false)

        // THEN
        #expect(login.isEnabled)
        #expect(login.message != nil)
        #expect(service.unregisterCount == 1)
    }

    @Test func `retrying unregister clears the error after disabling login`() {
        let service = TestLoginItem(status: .enabled, nextStatus: .notRegistered, fails: true)
        let login = LoginItemController(service: service)

        // GIVEN
        login.setEnabled(false)
        service.fails = false

        // WHEN
        login.setEnabled(false)

        // THEN
        #expect(!login.isEnabled)
        #expect(login.message == nil)
        #expect(service.unregisterCount == 2)
    }

    @Test func `failed registration preserves disabled status and reports an error`() {
        let service = TestLoginItem(fails: true)
        let login = LoginItemController(service: service)

        // WHEN
        login.setEnabled(true)

        // THEN
        #expect(!login.isEnabled)
        #expect(login.status == .notRegistered)
        #expect(login.message != nil)
        #expect(service.registerCount == 1)
    }
}

extension DesktopTests {
    @MainActor
    struct CaptureSettingsTests {
        @Test(arguments: [CaptureMode.box, .freehand])
        func `saved capture mode reaches the native selection window`(mode: CaptureMode) throws {
            let storage = try SettingsFixture(storedMode: mode.rawValue)
            let selection = SelectionFixture()
            let capture = CaptureFixture(settings: storage.settings, selectionManager: selection.manager)

            // WHEN
            capture.start()

            // THEN
            #expect(capture.toolbar.mode == mode)
            #expect(try selection.view.mode == mode)
        }

        @Test(arguments: [CaptureMode.box, .freehand])
        func `a toolbar mode choice is persisted and used in the next session`(mode: CaptureMode) throws {
            let storage = try SettingsFixture(storedMode: (mode == .box ? CaptureMode.freehand : .box).rawValue)
            let selection = SelectionFixture()
            let capture = CaptureFixture(settings: storage.settings, selectionManager: selection.manager)

            // GIVEN
            capture.start()

            // WHEN
            capture.selectMode(mode)
            capture.cancel()
            capture.start()

            // THEN
            #expect(storage.restoredSettings().lastSelectionMode == mode)
            #expect(capture.selectedMode == mode)
            #expect(capture.toolbar.mode == mode)
            #expect(try selection.view.mode == mode)
        }

        @Test func `a new native capture reloads mode changed in settings`() throws {
            let storage = try SettingsFixture(storedMode: "box")
            let selection = SelectionFixture()
            let capture = CaptureFixture(settings: storage.settings, selectionManager: selection.manager)

            // GIVEN
            capture.start()
            capture.cancel()
            storage.settings.selectCaptureMode(.freehand)

            // WHEN
            capture.start()
            capture.selectMode(.freehand)

            // THEN
            #expect(capture.toolbar.mode == .freehand)
            #expect(try selection.view.mode == .freehand)
            #expect(storage.restoredSettings().lastSelectionMode == .freehand)
        }
    }

    @MainActor
    struct SettingsWindowTests {
        @Test func `settings window has its expected title size and close retention`() throws {
            let settings = try SettingsWindowFixture()
            let window = try settings.window
            #expect(window.title == "ScreenText Settings")
            #expect(window.contentView?.frame.size == CGSize(width: 420, height: 620))
            #expect(!window.isReleasedWhenClosed)
        }

        @Test func `reopening settings shows the same window`() throws {
            let settings = try SettingsWindowFixture()
            let window = try settings.window

            // GIVEN
            settings.controller.show()
            window.close()
            #expect(!window.isVisible)

            // WHEN
            settings.controller.show()

            // THEN
            #expect(settings.controller.window === window)
            #expect(window.isVisible)
        }

        @Test func `showing settings refreshes externally changed statuses`() throws {
            let settings = try SettingsWindowFixture()

            // GIVEN
            settings.permission.allowed = true
            settings.service.status = .enabled

            // WHEN
            settings.controller.show()

            // THEN
            #expect(settings.permission.manager.hasScreenRecordingAccess)
            #expect(settings.login.status == .enabled)
        }

        @Test func `reactivating visible settings refreshes external statuses`() throws {
            let settings = try SettingsWindowFixture()

            // GIVEN
            settings.permission.allowed = true
            settings.service.status = .enabled
            settings.controller.show()
            settings.permission.allowed = false
            settings.service.status = .notRegistered

            // WHEN
            settings.reactivate()

            // THEN
            #expect(!settings.permission.manager.hasScreenRecordingAccess)
            #expect(settings.login.status == .notRegistered)
        }

        @Test func `hidden settings defer external status refresh until shown again`() throws {
            let settings = try SettingsWindowFixture()

            // GIVEN
            settings.controller.show()
            try settings.window.orderOut(nil)
            settings.permission.allowed = true
            settings.service.status = .enabled

            // WHEN
            settings.reactivate()

            // THEN
            #expect(!settings.permission.manager.hasScreenRecordingAccess)
            #expect(settings.login.status == .notRegistered)
            settings.controller.show()
            #expect(settings.permission.manager.hasScreenRecordingAccess)
            #expect(settings.login.status == .enabled)
        }
    }

    @MainActor
    struct ShortcutSettingsTests {
        @Test func `a custom shortcut persists and supplies its menu equivalent`() {
            let shortcut = ShortcutSettingsFixture()

            // WHEN
            KeyboardShortcuts.setShortcut(shortcut.combination, for: shortcut.name)

            // THEN
            let restored = KeyboardShortcuts.Name(shortcut.name.rawValue)
            #expect(KeyboardShortcuts.getShortcut(for: restored) == shortcut.combination)
            #expect(shortcut.item.keyEquivalent == "k")
            #expect(shortcut.item.keyEquivalentModifierMask == [.command, .option])
        }

        @Test func `clearing a shortcut removes its stored value and menu key`() {
            let shortcut = ShortcutSettingsFixture()

            // GIVEN
            KeyboardShortcuts.setShortcut(shortcut.combination, for: shortcut.name)

            // WHEN
            KeyboardShortcuts.setShortcut(nil, for: shortcut.name)

            // THEN
            #expect(KeyboardShortcuts.getShortcut(for: KeyboardShortcuts.Name(shortcut.name.rawValue)) == nil)
            #expect(shortcut.item.keyEquivalent.isEmpty)
        }
    }
}

@MainActor
private final class PermissionFixture {
    var allowed = false
    private let requestGrantsAccess: Bool
    private(set) var requests = 0
    private(set) var settingsOpens = 0
    private(set) lazy var manager = PermissionManager(checkAccess: { [weak self] in self?.allowed ?? false },
                                                      requestAccess: { [weak self] in
                                                          guard let self else { return false }
                                                          self.requests += 1
                                                          if self.requestGrantsAccess {
                                                              self.allowed = true
                                                          }
                                                          return self.allowed
                                                      }, openSettings: { [weak self] in self?.settingsOpens += 1 })

    init(requestGrantsAccess: Bool = false) {
        self.requestGrantsAccess = requestGrantsAccess
    }
}

@MainActor
private final class TestLoginItem: LoginItemManaging {
    var status: SMAppService.Status
    var nextStatus: SMAppService.Status
    var fails: Bool
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    enum Failure: Error { case unavailable }

    init(status: SMAppService.Status = .notRegistered, nextStatus: SMAppService.Status = .enabled,
         fails: Bool = false)
    {
        self.status = status
        self.nextStatus = nextStatus
        self.fails = fails
    }

    func register() throws {
        self.registerCount += 1
        if self.fails {
            throw Failure.unavailable
        }
        self.status = self.nextStatus
    }

    func unregister() throws {
        self.unregisterCount += 1
        if self.fails {
            throw Failure.unavailable
        }
        self.status = self.nextStatus
    }
}

@MainActor
private final class SettingsWindowFixture {
    let storage: SettingsFixture
    let permission = PermissionFixture()
    let service = TestLoginItem()
    let login: LoginItemController
    let controller: SettingsWindowController
    var window: NSWindow {
        get throws { try #require(self.controller.window) }
    }

    init() throws {
        self.storage = try SettingsFixture()
        self.login = LoginItemController(service: self.service)
        self.controller = SettingsWindowController(
            settings: self.storage.settings, permissions: self.permission.manager, login: self.login,
        )
    }

    func reactivate() {
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    }

    isolated deinit { controller.window?.close() }
}

@MainActor
private final class ShortcutSettingsFixture {
    let name = KeyboardShortcuts.Name("testShortcut_\(UUID().uuidString)")
    let item = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
    let combination = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])

    init() {
        KeyboardShortcuts.disable(self.name)
        self.item.setShortcut(for: self.name)
    }

    isolated deinit { KeyboardShortcuts.setShortcut(nil, for: name) }
}

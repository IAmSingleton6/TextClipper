import AppKit
import KeyboardShortcuts
@testable import ScreenText
import ServiceManagement
import Testing

@MainActor
struct SettingsTests {
    @Test func `initial settings only open once across launches`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(persistence: SettingsPersistence(defaults: defaults))
        #expect(settings.consumeFirstLaunch())
        #expect(!settings.consumeFirstLaunch())
        #expect(!SettingsStore(persistence: SettingsPersistence(defaults: defaults)).consumeFirstLaunch())
    }

    @Test func `permission request and external changes refresh status`() {
        var allowed = false
        var requests = 0
        var settingsOpens = 0
        let permissions = PermissionManager(checkAccess: { allowed }, requestAccess: {
            requests += 1
            return allowed
        }, openSettings: { settingsOpens += 1 })
        #expect(!permissions.hasScreenRecordingAccess && requests == 0)
        permissions.enableScreenRecording()
        #expect(requests == 1 && settingsOpens == 1)
        allowed = true
        permissions.refresh()
        #expect(permissions.hasScreenRecordingAccess)
        permissions.enableScreenRecording()
        #expect(requests == 2 && settingsOpens == 1)
        allowed = false
        permissions.refresh()
        #expect(!permissions.hasScreenRecordingAccess)
    }

    @Test func `preferences persist and invalid mode falls back to box`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(persistence: SettingsPersistence(defaults: defaults))
        #expect(settings.lastSelectionMode == .box && settings.showCapturedText)
        settings.selectCaptureMode(.freehand)
        settings.showCapturedText = false
        let restored = SettingsStore(persistence: SettingsPersistence(defaults: defaults))
        #expect(restored.lastSelectionMode == .freehand && !restored.showCapturedText)
        defaults.set("unknown", forKey: "lastSelectionMode")
        #expect(SettingsStore(persistence: SettingsPersistence(defaults: defaults)).lastSelectionMode == .box)
    }

    @Test(arguments: [CaptureMode.freehand, .box])
    func `capture modes use their raw values in existing storage`(mode: CaptureMode) throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(mode.rawValue, forKey: "lastSelectionMode")
        let settings = SettingsStore(persistence: SettingsPersistence(defaults: defaults))
        #expect(settings.lastSelectionMode == mode)
        settings.selectCaptureMode(mode == .box ? .freehand : .box)
        #expect(defaults.string(forKey: "lastSelectionMode") == settings.lastSelectionMode.rawValue)
        #expect(SettingsStore(persistence: SettingsPersistence(defaults: defaults)).lastSelectionMode == settings
            .lastSelectionMode)
    }

    @Test func `circle is not a supported capture mode`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("circle", forKey: "lastSelectionMode")
        #expect(SettingsStore(persistence: SettingsPersistence(defaults: defaults)).lastSelectionMode == .box)
    }

    @Test func `capture uses saved mode on each new session`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(persistence: SettingsPersistence(defaults: defaults))
        settings.selectCaptureMode(.freehand)
        let manager = SelectionManager()
        defer { manager.hide() }
        let toolbar = TestCaptureToolbar()
        let display = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                                       visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(),
                                           captureService: TestScreenCaptureService(), toolbar: toolbar,
                                           selectionManager: manager,
                                           displayProvider: { display },
                                           savedModeProvider: { settings.lastSelectionMode },
                                           saveMode: { settings.selectCaptureMode($0) })
        controller.start()
        #expect(toolbar.mode == .freehand)
        #expect(manager.window?.selectionView.mode == .freehand)
        controller.selectMode(.box)
        #expect(SettingsStore(persistence: SettingsPersistence(defaults: defaults)).lastSelectionMode == .box)
        controller.cancel()
        controller.start()
        #expect(controller.selectedMode == .box)
        controller.cancel()
        settings.selectCaptureMode(.freehand)
        controller.start()
        #expect(toolbar.mode == .freehand)
        #expect(manager.window?.selectionView.mode == .freehand)
        controller.selectMode(.freehand)
        #expect(SettingsStore(persistence: SettingsPersistence(defaults: defaults)).lastSelectionMode == .freehand)
        controller.cancel()
    }

    @Test func `login status reflects approval external changes and failures`() {
        let service = TestLoginItem()
        let controller = LoginItemController(service: service)
        #expect(!controller.isEnabled && service.registerCount == 0)
        service.nextStatus = .requiresApproval
        controller.isEnabled = true
        #expect(controller.isEnabled && controller.status == .requiresApproval)
        #expect(service.registerCount == 1)
        service.status = .enabled
        controller.refresh()
        #expect(controller.status == .enabled)
        service.fails = true
        controller.setEnabled(false)
        #expect(controller.isEnabled && controller.message != nil)
        service.fails = false
        service.nextStatus = .notRegistered
        controller.setEnabled(false)
        #expect(!controller.isEnabled && controller.message == nil)
        #expect(service.unregisterCount == 2)
    }

    @Test func `settings window reuses its window after closing`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = SettingsWindowController(
            settings: SettingsStore(persistence: SettingsPersistence(defaults: defaults)),
            login: LoginItemController(service: TestLoginItem()),
        )
        let window = try #require(controller.window)
        #expect(window.title == "ScreenText Settings")
        #expect(window.contentView?.frame.size == CGSize(width: 420, height: 620))
        window.close()
        #expect(controller.window === window)
        #expect(!window.isReleasedWhenClosed)
    }

    @Test func `settings refreshes external statuses when shown and reactivated`() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var allowed = false
        let permissions = PermissionManager(checkAccess: { allowed })
        let service = TestLoginItem()
        let login = LoginItemController(service: service)
        let controller = SettingsWindowController(
            settings: SettingsStore(persistence: SettingsPersistence(defaults: defaults)),
            permissions: permissions,
            login: login,
        )
        let window = try #require(controller.window)
        defer { window.close() }

        allowed = true
        service.status = .enabled
        controller.show()
        #expect(permissions.hasScreenRecordingAccess)
        #expect(login.status == .enabled)

        allowed = false
        service.status = .notRegistered
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        #expect(!permissions.hasScreenRecordingAccess)
        #expect(login.status == .notRegistered)

        window.orderOut(nil)
        allowed = true
        service.status = .enabled
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        #expect(!permissions.hasScreenRecordingAccess)
        #expect(login.status == .notRegistered)
        controller.show()
        #expect(permissions.hasScreenRecordingAccess)
        #expect(login.status == .enabled)
    }
}

@MainActor private final class TestLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var nextStatus: SMAppService.Status = .enabled
    var fails = false
    var registerCount = 0
    var unregisterCount = 0
    enum Failure: Error { case unavailable }
    func register() throws {
        self.registerCount += 1; if self.fails {
            throw Failure.unavailable
        }; self.status = self.nextStatus
    }

    func unregister() throws {
        self.unregisterCount += 1; if self.fails {
            throw Failure.unavailable
        }; self.status = self.nextStatus
    }
}

@Suite(.serialized) @MainActor
struct ShortcutSettingsTests {
    @Test func `package persists custom shortcut and updates menu equivalent`() {
        // Unique name avoids changing the user's capture shortcut or claiming a real combination.
        let name = KeyboardShortcuts.Name("testShortcut_\(UUID().uuidString)")
        KeyboardShortcuts.disable(name)
        defer { KeyboardShortcuts.setShortcut(nil, for: name) }
        let item = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        item.setShortcut(for: name)
        let shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        let restored = KeyboardShortcuts.Name(name.rawValue)
        #expect(KeyboardShortcuts.getShortcut(for: restored) == shortcut)
        #expect(item.keyEquivalent == "k")
        #expect(item.keyEquivalentModifierMask == [.command, .option])
        KeyboardShortcuts.setShortcut(nil, for: name)
        #expect(KeyboardShortcuts.getShortcut(for: restored) == nil)
        #expect(item.keyEquivalent.isEmpty)
    }
}

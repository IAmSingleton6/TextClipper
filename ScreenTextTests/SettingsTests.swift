import AppKit
import KeyboardShortcuts
import ServiceManagement
import Testing
@testable import ScreenText

@Suite @MainActor
struct SettingsTests {
    @Test func preferencesPersistAndInvalidModeFallsBackToBox() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.defaultMode == .box && !settings.showCapturedText)
        settings.defaultMode = .freehand
        settings.showCapturedText = true
        let restored = SettingsStore(defaults: defaults)
        #expect(restored.defaultMode == .freehand && restored.showCapturedText)
        defaults.set("unknown", forKey: "defaultSelectionMode")
        #expect(SettingsStore(defaults: defaults).defaultMode == .box)
    }

    @Test func captureUsesSavedModeOnEachNewSession() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.defaultMode = .freehand
        let manager = SelectionManager()
        defer { manager.hide() }
        let toolbar = TestCaptureToolbar()
        let display = SelectionDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                                       visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(),
            captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: manager,
            displayProvider: { display }, defaultModeProvider: { settings.defaultMode })
        controller.start()
        #expect(toolbar.model?.mode == .freehand)
        #expect(manager.window?.selectionView.mode == .freehand)
        controller.selectMode(.box)
        controller.cancel()
        controller.start()
        #expect(controller.selectedMode == .freehand)
        controller.cancel()
        settings.defaultMode = .box
        controller.start()
        #expect(toolbar.model?.mode == .box)
        #expect(manager.window?.selectionView.mode == .box)
        controller.cancel()
    }

    @Test func loginStatusReflectsApprovalExternalChangesAndFailures() {
        let service = TestLoginItem()
        let controller = LoginItemController(service: service)
        #expect(!controller.isOn && service.registerCount == 0)
        service.nextStatus = .requiresApproval
        controller.setEnabled(true)
        #expect(controller.isOn && controller.status == .requiresApproval)
        #expect(service.registerCount == 1)
        service.status = .enabled
        controller.refresh()
        #expect(controller.status == .enabled)
        service.fails = true
        controller.setEnabled(false)
        #expect(controller.isOn && controller.message != nil)
        service.fails = false
        service.nextStatus = .notRegistered
        controller.setEnabled(false)
        #expect(!controller.isOn && controller.message == nil)
        #expect(service.unregisterCount == 2)
    }

    @Test func settingsWindowReusesItsWindowAfterClosing() throws {
        let name = "com.screentext.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = SettingsWindowController(settings: SettingsStore(defaults: defaults),
                                                  login: LoginItemController(service: TestLoginItem()))
        let window = try #require(controller.window)
        #expect(window.title == "ScreenText Settings")
        #expect(window.contentView?.frame.size == CGSize(width: 420, height: 430))
        window.close()
        #expect(controller.window === window)
        #expect(!window.isReleasedWhenClosed)
    }
}

@MainActor private final class TestLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var nextStatus: SMAppService.Status = .enabled
    var fails = false
    var registerCount = 0
    var unregisterCount = 0
    enum Failure: Error { case unavailable }
    func register() throws { registerCount += 1; if fails { throw Failure.unavailable }; status = nextStatus }
    func unregister() throws { unregisterCount += 1; if fails { throw Failure.unavailable }; status = nextStatus }
}

@Suite(.serialized) @MainActor
struct ShortcutSettingsTests {
    @Test func packagePersistsCustomShortcutAndUpdatesMenuEquivalent() {
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

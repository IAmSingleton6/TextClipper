import Carbon.HIToolbox
import KeyboardShortcuts
@testable import ScreenText
import Testing

@Suite(.serialized) @MainActor
struct GlobalShortcutManagerTests {
    @Test func `injected source delivers captures and supports restart`() {
        let source = TestShortcutSource()
        var captures = 0
        let manager = GlobalShortcutManager(source: source) { captures += 1 }

        manager.stop()
        #expect(source.stops == 0)
        manager.start()
        manager.start()
        #expect(source.starts == 1)
        source.onTrigger?()
        #expect(captures == 1)

        manager.stop()
        manager.stop()
        #expect(source.stops == 1)
        source.onTrigger?()
        #expect(captures == 1)

        manager.start()
        #expect(source.starts == 2)
        source.onTrigger?()
        #expect(captures == 2)
        manager.stop()
    }

    @Test func `releasing manager stops a retained source`() {
        let source = TestShortcutSource()
        var manager: GlobalShortcutManager? = GlobalShortcutManager(source: source, onCapture: {})
        manager?.start()
        manager = nil
        #expect(source.stops == 1)
        #expect(source.onTrigger == nil)
    }

    @Test func `registers default shortcut and releases it on stop`() throws {
        // The hosted app also listens to this name. Temporarily disable it to establish
        // that no other application already owns the combination, then restore it.
        let savedShortcut = KeyboardShortcuts.getShortcut(for: AppShortcuts.captureText)
        KeyboardShortcuts.disable(AppShortcuts.captureText)
        defer {
            KeyboardShortcuts.setShortcut(savedShortcut, for: AppShortcuts.captureText)
            KeyboardShortcuts.enable(AppShortcuts.captureText)
        }
        let initialShortcut = AppShortcuts.captureText.initialShortcut
        #expect(initialShortcut == .init(.two, modifiers: [.command, .shift]))
        KeyboardShortcuts.setShortcut(initialShortcut, for: AppShortcuts.captureText)
        KeyboardShortcuts.disable(AppShortcuts.captureText)

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x5354_5453, id: 1)
        func tryRegister() -> OSStatus {
            RegisterEventHotKey(
                UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey), identifier,
                GetApplicationEventTarget(), 0, &reference,
            )
        }
        func releaseProbe() {
            if let reference {
                UnregisterEventHotKey(reference)
            }
            reference = nil
        }
        defer { releaseProbe() }

        try #require(tryRegister() == noErr, "Another app owns Command-Shift-2")
        releaseProbe()

        let manager = GlobalShortcutManager(
            source: KeyboardShortcutSource(name: AppShortcuts.captureText),
            onCapture: {},
        )
        defer { manager.stop() }
        manager.start()
        manager.start()
        #expect(tryRegister() == eventHotKeyExistsErr, "Starting must claim the system hotkey")
        manager.stop()
        try #require(tryRegister() == noErr, "Stopping must release the system hotkey")
        releaseProbe()

        manager.start()
        #expect(tryRegister() == eventHotKeyExistsErr, "Restarting must register the hotkey again")
    }
}

@MainActor
private final class TestShortcutSource: ShortcutSource {
    var starts = 0
    var stops = 0
    var onTrigger: (() -> Void)?

    func startListening(onTrigger: @escaping () -> Void) {
        self.starts += 1
        self.onTrigger = onTrigger
    }

    func stopListening() {
        self.stops += 1
        self.onTrigger = nil
    }
}

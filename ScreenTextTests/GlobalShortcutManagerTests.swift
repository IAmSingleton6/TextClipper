import Carbon.HIToolbox
import KeyboardShortcuts
@testable import ScreenText
import Testing

extension DesktopTests {
    @MainActor
    struct GlobalShortcutManagerTests {
        @Test func `stopping before listening has no effect`() {
            let shortcut = ShortcutFixture()
            shortcut.manager.stop()
            #expect(shortcut.source.stops == 0)
        }

        @Test func `starting twice subscribes only once`() {
            let shortcut = ShortcutFixture()

            // GIVEN
            shortcut.manager.start()

            // WHEN
            shortcut.manager.start()

            // THEN
            #expect(shortcut.source.starts == 1)
        }

        @Test func `a shortcut trigger requests one capture`() {
            let shortcut = ShortcutFixture()

            // GIVEN
            shortcut.manager.start()

            // WHEN
            shortcut.trigger()

            // THEN
            #expect(shortcut.captures == 1)
        }

        @Test func `stopping twice unsubscribes only once`() {
            let shortcut = ShortcutFixture()

            // GIVEN
            shortcut.manager.start()
            shortcut.manager.stop()

            // WHEN
            shortcut.manager.stop()

            // THEN
            #expect(shortcut.source.stops == 1)
        }

        @Test func `a stopped shortcut no longer requests captures`() {
            let shortcut = ShortcutFixture()

            // GIVEN
            shortcut.manager.start()
            shortcut.trigger()
            shortcut.manager.stop()

            // WHEN
            shortcut.trigger()

            // THEN
            #expect(shortcut.captures == 1)
        }

        @Test func `restarting restores shortcut delivery`() {
            let shortcut = ShortcutFixture()

            // GIVEN
            shortcut.manager.start()
            shortcut.trigger()
            shortcut.manager.stop()

            // WHEN
            shortcut.manager.start()
            shortcut.trigger()

            // THEN
            #expect(shortcut.source.starts == 2)
            #expect(shortcut.captures == 2)
        }

        @Test func `releasing a manager stops its retained source`() {
            let source = TestShortcutSource()
            var manager: GlobalShortcutManager? = GlobalShortcutManager(source: source, onCapture: {})

            // GIVEN
            manager?.start()

            // WHEN
            manager = nil

            // THEN
            #expect(source.stops == 1)
            #expect(source.onTrigger == nil)
        }

        @Test func `the initial capture shortcut is Command Shift 2`() {
            #expect(AppShortcuts.captureText.initialShortcut == .init(.two, modifiers: [.command, .shift]))
        }

        @Test func `starting a native shortcut claims its system hotkey`() throws {
            let shortcut = try NativeShortcutFixture()

            // WHEN
            shortcut.manager.start()
            shortcut.manager.start()

            // THEN
            #expect(shortcut.probeRegistration() == eventHotKeyExistsErr)
        }

        @Test func `stopping a native shortcut releases its system hotkey`() throws {
            let shortcut = try NativeShortcutFixture()

            // GIVEN
            shortcut.manager.start()
            try #require(shortcut.probeRegistration() == eventHotKeyExistsErr)

            // WHEN
            shortcut.manager.stop()

            // THEN
            #expect(shortcut.probeRegistration() == noErr)
        }

        @Test func `restarting a native shortcut reclaims its system hotkey`() throws {
            let shortcut = try NativeShortcutFixture()

            // GIVEN
            shortcut.manager.start()
            shortcut.manager.stop()
            try #require(shortcut.probeRegistration() == noErr)
            shortcut.releaseProbe()

            // WHEN
            shortcut.manager.start()

            // THEN
            #expect(shortcut.probeRegistration() == eventHotKeyExistsErr)
        }
    }
}

@MainActor
private final class ShortcutFixture {
    let source = TestShortcutSource()
    private(set) var captures = 0
    private(set) lazy var manager = GlobalShortcutManager(source: self.source) { [weak self] in self?.captures += 1 }
    func trigger() {
        self.source.onTrigger?()
    }

    isolated deinit { manager.stop() }
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

@MainActor
private final class NativeShortcutFixture {
    private let name = KeyboardShortcuts.Name("nativeShortcut_\(UUID().uuidString)")
    private var reference: EventHotKeyRef?
    let manager: GlobalShortcutManager

    init() throws {
        KeyboardShortcuts.disable(self.name)
        KeyboardShortcuts.setShortcut(.init(.k, modifiers: [.command, .option, .control, .shift]), for: self.name)
        self.manager = GlobalShortcutManager(source: KeyboardShortcutSource(name: self.name), onCapture: {})
        try #require(self.probeRegistration() == noErr, "Another app owns the isolated test combination")
        self.releaseProbe()
    }

    func probeRegistration() -> OSStatus {
        RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(cmdKey | optionKey | controlKey | shiftKey),
                            EventHotKeyID(signature: 0x5354_5453, id: 1), GetApplicationEventTarget(), 0,
                            &self.reference)
    }

    func releaseProbe() {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        self.reference = nil
    }

    isolated deinit {
        manager.stop()
        if let reference {
            UnregisterEventHotKey(reference)
        }
        KeyboardShortcuts.disable(name)
        KeyboardShortcuts.setShortcut(nil, for: name)
    }
}

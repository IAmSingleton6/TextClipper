import Carbon.HIToolbox
import KeyboardShortcuts
import Testing
@testable import ScreenText

@Suite(.serialized) @MainActor
struct GlobalShortcutManagerTests {
    @Test func registersDefaultShortcutAndReleasesItOnStop() throws {
        // The hosted app also listens to this name. Temporarily disable it to establish
        // that no other application already owns the combination, then restore it.
        KeyboardShortcuts.disable(.captureText)
        defer { KeyboardShortcuts.enable(.captureText) }
        #expect(KeyboardShortcuts.getShortcut(for: .captureText) == .init(.space, modifiers: [.command, .shift]))

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x53545453, id: 1)
        func tryRegister() -> OSStatus {
            RegisterEventHotKey(
                UInt32(kVK_Space), UInt32(cmdKey | shiftKey), identifier,
                GetApplicationEventTarget(), 0, &reference
            )
        }
        func releaseProbe() {
            if let reference { UnregisterEventHotKey(reference) }
            reference = nil
        }
        defer { releaseProbe() }

        try #require(tryRegister() == noErr, "Another app owns Command-Shift-Space")
        releaseProbe()

        let manager = GlobalShortcutManager(onCapture: {})
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

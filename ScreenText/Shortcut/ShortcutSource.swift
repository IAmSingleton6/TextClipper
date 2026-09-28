import KeyboardShortcuts

/// Owns shortcut registration and delivers one trigger per completed key press.
@MainActor
protocol ShortcutSource: AnyObject {
    func startListening(onTrigger: @escaping () -> Void)
    func stopListening()
}

@MainActor
final class KeyboardShortcutSource: ShortcutSource {
    private let name: KeyboardShortcuts.Name
    private var listeningTask: Task<Void, Never>?

    init(name: KeyboardShortcuts.Name) {
        self.name = name
    }

    func startListening(onTrigger: @escaping () -> Void) {
        guard self.listeningTask == nil else { return }

        KeyboardShortcuts.enable(self.name)

        let events = KeyboardShortcuts.events(for: self.name)
        self.listeningTask = Task {
            for await event in events where event == .keyUp {
                guard !Task.isCancelled else { return }
                onTrigger()
            }
        }
    }

    func stopListening() {
        self.listeningTask?.cancel()
        self.listeningTask = nil
        KeyboardShortcuts.disable(self.name)
    }

    deinit {
        listeningTask?.cancel()
    }
}

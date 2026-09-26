import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureText = Self(
        "captureText",
        initial: .init(.space, modifiers: [.command, .shift])
    )
}

@MainActor
final class GlobalShortcutManager {
    private let onCapture: () -> Void
    private var listeningTask: Task<Void, Never>?

    init(onCapture: @escaping () -> Void) {
        self.onCapture = onCapture
    }

    func start() {
        guard listeningTask == nil else { return }
        KeyboardShortcuts.enable(.captureText)
        let events = KeyboardShortcuts.events(for: .captureText)
        let onCapture = onCapture
        listeningTask = Task {
            // Key-up delivers one invocation per press, even when the key is held.
            for await event in events where event == .keyUp {
                guard !Task.isCancelled else { return }
                onCapture()
            }
        }
    }

    func stop() {
        listeningTask?.cancel()
        listeningTask = nil
        KeyboardShortcuts.disable(.captureText)
    }

    deinit {
        listeningTask?.cancel()
    }
}

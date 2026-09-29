import KeyboardShortcuts

@MainActor
protocol EscapeMonitoring: AnyObject {
    func start(onEscape: @escaping () -> Void)
    func stop()
}

@MainActor
final class EscapeMonitor: EscapeMonitoring {
    private var task: Task<Void, Never>?

    func start(onEscape: @escaping () -> Void) {
        self.stop()

        // Listen only during a capture session; this needs no Accessibility
        // permission or persistent Escape shortcut setting.
        let events = KeyboardShortcuts.events(for: .init(.escape, modifiers: []))
        self.task = Task {
            for await event in events where event == .keyDown {
                guard !Task.isCancelled else { return }
                onEscape()
            }
        }
    }

    func stop() {
        self.task?.cancel()
        self.task = nil
    }

    deinit {
        task?.cancel()
    }
}

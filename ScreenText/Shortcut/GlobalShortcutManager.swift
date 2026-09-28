@MainActor
final class GlobalShortcutManager {
    private let source: any ShortcutSource
    private let onCapture: () -> Void
    private var isListening = false

    init(source: any ShortcutSource, onCapture: @escaping () -> Void) {
        self.source = source
        self.onCapture = onCapture
    }

    func start() {
        guard !self.isListening else { return }
        self.isListening = true
        self.source.startListening(onTrigger: self.onCapture)
    }

    func stop() {
        guard self.isListening else { return }
        self.isListening = false
        self.source.stopListening()
    }

    isolated deinit {
        guard self.isListening else { return }
        source.stopListening()
    }
}

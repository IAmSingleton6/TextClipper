import KeyboardShortcuts

@MainActor
final class CaptureController {
    private(set) var isActive = false
    var selectedMode: CaptureMode { toolbarModel.mode }
    var onActivityChanged: ((Bool) -> Void)?

    private let toolbar: any CaptureToolbarPresenting
    private let toolbarModel = CaptureToolbarModel()
    private var escapeTask: Task<Void, Never>?

    init(toolbar: any CaptureToolbarPresenting = CaptureToolbarWindow()) {
        self.toolbar = toolbar
    }

    func toggle() {
        if isActive {
            cancel()
        } else {
            start()
        }
    }

    func start() {
        guard !isActive else { return }
        toolbarModel.mode = .box
        guard toolbar.show(
            model: toolbarModel,
            onModeSelected: { [weak self] mode in self?.selectMode(mode) },
            onCancel: { [weak self] in self?.cancel() }
        ) else { return }
        isActive = true
        onActivityChanged?(true)
        listenForEscape()
    }

    func selectMode(_ mode: CaptureMode) {
        guard isActive else { return }
        toolbarModel.mode = mode
    }

    func cancel() {
        guard isActive else { return }
        escapeTask?.cancel()
        escapeTask = nil
        toolbar.hide()
        isActive = false
        onActivityChanged?(false)
    }

    private func listenForEscape() {
        // Register only during a capture session; no Accessibility permission or
        // persistent Escape shortcut setting is needed.
        let events = KeyboardShortcuts.events(for: .init(.escape, modifiers: []))
        let onCancel = { [weak self] in self?.cancel() }
        escapeTask = Task {
            for await event in events where event == .keyDown {
                guard !Task.isCancelled else { return }
                onCancel()
            }
        }
    }

    deinit {
        escapeTask?.cancel()
    }
}

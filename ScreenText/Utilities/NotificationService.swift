import AppKit

@MainActor
protocol NotificationPresenting: AnyObject {
    func show(_ message: String, on display: SelectionDisplay?)
    func hide()
}

@MainActor
final class NotificationService: NotificationPresenting {
    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    func show(_ message: String, on display: SelectionDisplay? = nil) {
        hide()
        guard let frame = display?.visibleFrame ?? SelectionDisplay.atMouse()?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let size = CGSize(width: 320, height: 64)
        let panel = FeedbackPanel(contentRect: CGRect(x: frame.midX - size.width / 2,
                                                     y: frame.minY + 96, width: size.width, height: size.height),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.frame = CGRect(x: 16, y: 18, width: 288, height: 30)
        background.addSubview(label)
        panel.contentView = background
        self.panel = panel
        panel.showFeedback()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissalTask?.cancel()
        dismissalTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    deinit { dismissalTask?.cancel() }
}

private final class FeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

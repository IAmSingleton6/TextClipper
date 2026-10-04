import AppKit

@MainActor
protocol NotificationPresenting: AnyObject {
    func show(_ message: String, on display: SelectionDisplay?, dismissAfter: Duration?)
    func hide()
}

extension NotificationPresenting {
    func show(_ message: String, on display: SelectionDisplay?) {
        self.show(message, on: display, dismissAfter: .seconds(3))
    }
}

@MainActor
final class NotificationService: NotificationPresenting {
    private var panel: NotificationPanel?
    private var dismissalTask: Task<Void, Never>?

    func show(_ message: String, on display: SelectionDisplay? = nil, dismissAfter: Duration? = .seconds(3)) {
        self.hide()

        guard let visibleFrame = display?.visibleFrame
            ?? SelectionDisplay.atMouse()?.visibleFrame
            ?? NSScreen.main.map({ ScreenRect(appKitGlobalRect: $0.visibleFrame) })
        else {
            return
        }

        let size = NotificationPanel.size
        let panelFrame = CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 96,
            width: size.width,
            height: size.height,
        )
        let panel = NotificationPanel(message: message, frame: panelFrame)
        self.panel = panel
        panel.showFeedback()

        guard let dismissAfter else { return }
        self.dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: dismissAfter)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        self.dismissalTask?.cancel()
        self.dismissalTask = nil
        self.panel?.orderOut(nil)
        self.panel = nil
    }

    deinit { dismissalTask?.cancel() }
}

@MainActor
private final class NotificationPanel: NSPanel {
    static let size = CGSize(width: 320, height: 64)

    init(message: String, frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: Self.size))
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
        contentView = background
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

import AppKit
import SwiftUI

@MainActor
protocol CapturedTextPresenting: AnyObject {
    func show(_ text: String, on display: SelectionDisplay)
    func hide()
}

@MainActor
final class CapturedTextWindow: NSPanel, CapturedTextPresenting {
    private var dismissalTask: Task<Void, Never>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        title = "ScreenText Captured Text"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func show(_ text: String, on display: SelectionDisplay) {
        self.hide()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        contentView = CapturedTextHostingView(rootView: CapturedTextView(
            text: text,
            maximumWidth: max(1, display.visibleFrame.width - 32),
            onDismiss: { [weak self] in self?.hide() },
        ))

        self.position(on: display)
        showFeedback()
        self.scheduleDismissal()
    }

    func hide() {
        self.dismissalTask?.cancel()
        self.dismissalTask = nil
        orderOut(nil)
        contentView = nil
    }

    private func position(on display: SelectionDisplay) {
        guard let contentView else { return }

        setContentSize(contentView.fittingSize)

        let visible = display.visibleFrame
        let x = visible.midX - frame.width / 2
        let y = max(
            visible.minY,
            min(visible.minY + 96, visible.maxY - frame.height),
        )

        setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func scheduleDismissal() {
        self.dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    deinit { dismissalTask?.cancel() }
}

private final class CapturedTextHostingView: NSHostingView<CapturedTextView> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

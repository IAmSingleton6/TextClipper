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
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "ScreenText Captured Text"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
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
        let host = NSHostingView(rootView: CapturedTextView(text: text))
        contentView = host
        setContentSize(host.fittingSize)
        let visible = display.visibleFrame
        setFrameOrigin(CGPoint(x: visible.midX - frame.width / 2,
                               y: min(visible.minY + 96, visible.maxY - frame.height)))
        showFeedback()
        self.dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        self.dismissalTask?.cancel()
        self.dismissalTask = nil
        orderOut(nil)
        // Release the preview text, including the SwiftUI hosting tree.
        contentView = nil
    }

    deinit { dismissalTask?.cancel() }
}

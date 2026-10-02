import AppKit

@MainActor
final class SelectionWindow: NSWindow {
    let selectionView: SelectionView

    init(displayFrame: CGRect) {
        self.selectionView = SelectionView(frame: CGRect(origin: .zero, size: displayFrame.size))
        super.init(contentRect: displayFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        title = "ScreenText Selection"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        contentView = self.selectionView
        self.selectionView.setAccessibilityLabel("Text selection area")
        self.selectionView.setAccessibilityHelp("Drag around text using the selected shape. Press Escape to cancel.")
    }

    /// This overlay deliberately covers the full display, including the menu bar.
    /// AppKit's normal visible-frame constraint can otherwise shift its origin.
    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

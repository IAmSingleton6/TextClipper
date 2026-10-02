import AppKit

@MainActor
final class SelectionWindow: NSPanel {
    let selectionView: SelectionView

    init(displayFrame: CGRect) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: displayFrame.size))
        super.init(contentRect: displayFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "ScreenText Selection"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        contentView = selectionView
        selectionView.setAccessibilityLabel("Text selection area")
        selectionView.setAccessibilityHelp("Drag around text using the selected shape. Press Escape to cancel.")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

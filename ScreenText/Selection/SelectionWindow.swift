import AppKit

@MainActor
final class SelectionWindow: NSWindow {
    let selectionView: SelectionView
    private var cursorTimer: Timer?
    private var cursorExclusionRect: ScreenRect?

    var mode: CaptureMode {
        get { self.selectionView.mode }
        set { self.selectionView.mode = newValue }
    }

    var onSelectionEvent: ((SelectionEvent<SelectionGeometry>) -> Void)? {
        get { self.selectionView.onEvent }
        set { self.selectionView.onEvent = newValue }
    }

    init(displayFrame: ScreenRect) {
        self.selectionView = SelectionView(frame: CGRect(origin: .zero, size: displayFrame.appKitGlobalRect.size))
        super.init(
            contentRect: displayFrame.appKitGlobalRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )

        self.configureOverlay()
        contentView = self.selectionView
        self.selectionView.setAccessibilityLabel("Text selection area")
        self.selectionView.setAccessibilityHelp("Drag around text using the selected shape. Press Escape to cancel.")
    }

    private func configureOverlay() {
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
    }

    func presentForSelection() {
        // Claim main and key status so another window does not take focus
        // when the activation request completes.
        makeKeyAndOrderFront(nil)
        makeMain()
        orderFrontRegardless()
        makeFirstResponder(self.selectionView)
        displayIfNeeded()
        resetCursorRects()
        self.selectionView.updateTrackingAreas()
    }

    func reclaimSelectionFocus() {
        guard isVisible else { return }
        makeMain()
        makeKey()
        makeFirstResponder(self.selectionView)
        resetCursorRects()
        self.updateCursor()
    }

    func setCursorExclusionRect(_ rect: ScreenRect?) {
        self.cursorExclusionRect = rect
        self.updateCursor()
    }

    func startCursorMaintenance() {
        self.updateCursor()
        // Activation can reset a stationary pointer without sending a mouse
        // event. Keep the selection cursor current until the window is hidden.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in self.updateCursor() }
        }
        self.cursorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismissSelection() {
        self.stopCursorMaintenance()
        self.cursorExclusionRect = nil
        self.selectionView.reset()
        self.onSelectionEvent = nil
        orderOut(nil)
        NSCursor.arrow.set()
    }

    private func stopCursorMaintenance() {
        self.cursorTimer?.invalidate()
        self.cursorTimer = nil
    }

    private func updateCursor() {
        guard isVisible else { return }
        let cursor: NSCursor = self.cursorExclusionRect?
            .contains(ScreenPoint(appKitGlobalPoint: NSEvent.mouseLocation)) == true ? .arrow : .crosshair
        cursor.set()
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

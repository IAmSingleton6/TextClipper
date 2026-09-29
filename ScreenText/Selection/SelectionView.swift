import AppKit

@MainActor
final class SelectionView: NSView {
    // Both shapes use the same cursor. Invalidating cursor rects on a mode
    // click can replace the toolbar's arrow before the pointer leaves it.
    var mode: CaptureMode = .box
    var onEvent: ((SelectionEvent<SelectionGeometry>) -> Void)?
    private var drag: SelectionDrag?

    var selectionRect: CGRect? {
        self.drag?.bounds(for: self.mode)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        self.drag = SelectionDrag(start: self.clampedPoint(for: event))
        needsDisplay = true
        self.onEvent?(.started)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = self.drag else { return }
        drag.move(to: self.clampedPoint(for: event), mode: self.mode)
        self.drag = drag
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var drag = self.drag else { return }
        drag.move(to: self.clampedPoint(for: event), mode: self.mode)
        let geometry = drag.completedGeometry(for: self.mode)
        self.reset()

        if let geometry {
            self.onEvent?(.completed(geometry))
        } else {
            self.onEvent?(.cancelled)
        }
    }

    override func cancelOperation(_: Any?) {
        self.onEvent?(.cancelled)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            self.onEvent?(.cancelled)
        } else {
            super.keyDown(with: event)
        }
    }

    func reset() {
        self.drag = nil
        needsDisplay = true
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY),
        )
    }

    override func draw(_: NSRect) {
        SelectionOverlayDrawing().draw(in: bounds, mode: self.mode, drag: self.drag)
    }

    override var isOpaque: Bool {
        false
    }

    override var isFlipped: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var needsPanelToBecomeKey: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with _: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.crosshair.set()
    }
}

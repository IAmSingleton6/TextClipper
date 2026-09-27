import AppKit

@MainActor
final class SelectionView: NSView {
    var mode: CaptureMode = .box {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var onStarted: (() -> Void)?
    var onFinished: ((CGRect?) -> Void)?
    var onCancelled: (() -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return Selection.normalizedRect(from: startPoint, to: currentPoint)
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startPoint = clampedPoint(for: event)
        currentPoint = startPoint
        needsDisplay = true
        onStarted?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clampedPoint(for: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clampedPoint(for: event)
        let rect = selectionRect
        reset()
        onFinished?(rect.flatMap { Selection.isValid($0) ? $0 : nil })
    }

    override func cancelOperation(_ sender: Any?) {
        onCancelled?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancelled?()
        } else {
            super.keyDown(with: event)
        }
    }

    func reset() {
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func selectionPath(in rect: CGRect) -> NSBezierPath {
        mode == .box ? NSBezierPath(rect: rect) : NSBezierPath(ovalIn: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        guard let selectionRect else {
            // A minimally visible surface reliably receives the first mouse-down
            // instead of leaving a fully transparent WindowServer region.
            NSColor.black.withAlphaComponent(0.01).setFill()
            bounds.fill()
            return
        }

        let dimmedArea = NSBezierPath(rect: bounds)
        dimmedArea.append(selectionPath(in: selectionRect))
        dimmedArea.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        dimmedArea.fill()

        if selectionRect.width > 1 && selectionRect.height > 1 {
            let border = selectionPath(in: selectionRect.insetBy(dx: 0.5, dy: 0.5))
            // A dark under-stroke keeps the bright edge visible on light content.
            border.lineWidth = 3
            NSColor.black.withAlphaComponent(0.4).setStroke()
            border.stroke()
            border.lineWidth = 1
            NSColor.white.withAlphaComponent(0.85).setStroke()
            border.stroke()
        }
    }
}

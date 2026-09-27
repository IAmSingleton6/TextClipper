import AppKit

@MainActor
final class SelectionView: NSView {
    var mode: CaptureMode = .box {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var onStarted: (() -> Void)?
    var onFinished: ((SelectionGeometry?) -> Void)?
    var onCancelled: (() -> Void)?
    private var drawnPoints: [CGPoint] = []
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        if mode == .freehand { return SelectionGeometry.bounds(for: drawnPoints) }
        return Selection.normalizedRect(from: startPoint, to: currentPoint)
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startPoint = clampedPoint(for: event)
        currentPoint = startPoint
        drawnPoints = startPoint.map { [$0] } ?? []
        needsDisplay = true
        onStarted?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clampedPoint(for: event)
        appendDrawnPoint()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clampedPoint(for: event)
        appendDrawnPoint()
        let geometry: SelectionGeometry?
        if mode == .freehand {
            geometry = SelectionGeometry.freehand(points: drawnPoints)
        } else {
            geometry = selectionRect.flatMap { Selection.isValid($0) ? SelectionGeometry(rect: $0, shape: .rectangle) : nil }
        }
        reset()
        onFinished?(geometry)
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
        drawnPoints.removeAll()
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }

    private func appendDrawnPoint() {
        guard mode == .freehand, let point = currentPoint, drawnPoints.last != point else { return }
        drawnPoints.append(point)
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func selectionPath(in rect: CGRect) -> NSBezierPath {
        if mode == .box { return NSBezierPath(rect: rect) }
        let path = NSBezierPath()
        if let first = drawnPoints.first {
            path.move(to: first)
            for point in drawnPoints.dropFirst() { path.line(to: point) }
            path.close()
        }
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        guard let selectionRect else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.fill()
            return
        }

        let dimmedArea = NSBezierPath(rect: bounds)
        dimmedArea.append(selectionPath(in: selectionRect))
        dimmedArea.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        dimmedArea.fill()

        let hasBorder = mode == .freehand ? drawnPoints.count > 1 : selectionRect.width > 1 && selectionRect.height > 1
        if hasBorder {
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

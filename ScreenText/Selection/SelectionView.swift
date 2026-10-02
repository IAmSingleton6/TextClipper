import AppKit

enum SelectionEvent<Value> {
    case started
    case completed(Value)
    case cancelled
}

@MainActor
final class SelectionView: NSView {
    // Both shapes use the same cursor. Invalidating cursor rects on a mode
    // click can replace the toolbar's arrow before the pointer leaves it.
    var mode: CaptureMode = .box
    var onEvent: ((SelectionEvent<SelectionGeometry>) -> Void)?
    private var drawnPoints: [CGPoint] = []
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        if self.mode == .freehand {
            return SelectionGeometry.bounds(for: self.drawnPoints)
        }
        return Selection.normalizedRect(from: startPoint, to: currentPoint)
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

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        self.startPoint = self.clampedPoint(for: event)
        self.currentPoint = self.startPoint
        self.drawnPoints = self.startPoint.map { [$0] } ?? []
        needsDisplay = true
        self.onEvent?(.started)
    }

    override func mouseDragged(with event: NSEvent) {
        guard self.startPoint != nil else { return }
        self.currentPoint = self.clampedPoint(for: event)
        self.appendDrawnPoint()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard self.startPoint != nil else { return }
        self.currentPoint = self.clampedPoint(for: event)
        self.appendDrawnPoint()
        let geometry: SelectionGeometry? = if self.mode == .freehand {
            SelectionGeometry.freehand(points: self.drawnPoints)
        } else {
            self.selectionRect.flatMap { Selection.isValid($0) ? SelectionGeometry(rect: $0, shape: .rectangle) : nil }
        }
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
        self.drawnPoints.removeAll()
        self.startPoint = nil
        self.currentPoint = nil
        needsDisplay = true
    }

    private func appendDrawnPoint() {
        guard self.mode == .freehand, let point = currentPoint, drawnPoints.last != point else { return }
        self.drawnPoints.append(point)
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func selectionPath(in rect: CGRect) -> NSBezierPath {
        if self.mode == .box {
            return NSBezierPath(rect: rect)
        }
        let path = NSBezierPath()
        if let first = drawnPoints.first {
            path.move(to: first)
            for point in self.drawnPoints.dropFirst() {
                path.line(to: point)
            }
            path.close()
        }
        return path
    }

    override func draw(_: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        guard let selectionRect else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.fill()
            return
        }

        let dimmedArea = NSBezierPath(rect: bounds)
        dimmedArea.append(self.selectionPath(in: selectionRect))
        dimmedArea.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        dimmedArea.fill()

        let hasBorder = self.mode == .freehand ? self.drawnPoints.count > 1 : selectionRect.width > 1 && selectionRect
            .height > 1
        if hasBorder {
            let border = self.selectionPath(in: selectionRect.insetBy(dx: 0.5, dy: 0.5))
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

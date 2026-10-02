import AppKit

/// Draws the dimmed display and the selection's visible edge.
struct SelectionOverlayDrawing {
    func draw(in bounds: DisplayRect, mode: CaptureMode, drag: SelectionDrag?) {
        NSColor.clear.setFill()
        bounds.displayLocalRect.fill(using: .copy)

        guard let drag, let selectionRect = drag.bounds(for: mode) else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.displayLocalRect.fill()
            return
        }

        let dimmedArea = NSBezierPath(rect: bounds.displayLocalRect)
        dimmedArea.append(self.path(for: selectionRect, mode: mode, points: drag.points))
        dimmedArea.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        dimmedArea.fill()

        let hasBorder = mode == .freehand ? drag.points.count > 1 : selectionRect.width > 1 && selectionRect.height > 1
        guard hasBorder else { return }

        let border = self.path(for: selectionRect.insetBy(dx: 0.5, dy: 0.5), mode: mode, points: drag.points)
        // A dark under-stroke keeps the bright edge visible on light content.
        border.lineWidth = 3
        NSColor.black.withAlphaComponent(0.4).setStroke()
        border.stroke()
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.85).setStroke()
        border.stroke()
    }

    private func path(for rect: DisplayRect, mode: CaptureMode, points: [DisplayPoint]) -> NSBezierPath {
        guard mode == .freehand else { return NSBezierPath(rect: rect.displayLocalRect) }

        let path = NSBezierPath()
        if let first = points.first {
            path.move(to: first.displayLocalPoint)
            for point in points.dropFirst() {
                path.line(to: point.displayLocalPoint)
            }
            path.close()
        }
        return path
    }
}

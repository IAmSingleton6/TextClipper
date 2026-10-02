import CoreGraphics

/// The points collected during one mouse drag. Shape validation happens only
/// when the mouse is released.
struct SelectionDrag {
    let start: DisplayPoint
    private(set) var current: DisplayPoint
    private(set) var points: [DisplayPoint]

    init(start: DisplayPoint) {
        self.start = start
        self.current = start
        self.points = [start]
    }

    mutating func move(to point: DisplayPoint, mode: CaptureMode) {
        self.current = point
        if mode == .freehand, self.points.last != point {
            self.points.append(point)
        }
    }

    func bounds(for mode: CaptureMode) -> DisplayRect? {
        switch mode {
        case .box:
            Selection.normalizedRect(from: self.start, to: self.current)
        case .freehand:
            SelectionGeometry.bounds(for: self.points)
        }
    }

    func completedGeometry(for mode: CaptureMode) -> SelectionGeometry? {
        switch mode {
        case .box:
            guard let rect = self.bounds(for: mode), Selection.isValid(rect) else { return nil }
            return SelectionGeometry(rect: rect, shape: .rectangle)
        case .freehand:
            return SelectionGeometry.freehand(points: self.points)
        }
    }
}

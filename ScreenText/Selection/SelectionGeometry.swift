import CoreGraphics

/// A validated shape in display-local points, ready to send to capture.
struct SelectionGeometry: Equatable, Sendable {
    let rect: CGRect
    let shape: SelectionShape

    static func bounds(for points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let path = CGMutablePath()
        path.addLines(between: points)
        return path.boundingBoxOfPath
    }

    static func freehand(points: [CGPoint]) -> SelectionGeometry? {
        guard points.count >= 3,
              let bounds = self.bounds(for: points),
              Selection.isValid(bounds)
        else { return nil }

        let area = self.largestTriangleArea(in: points)
        guard area.isFinite, area >= 8 else { return nil }

        return SelectionGeometry(rect: bounds, shape: .freehand(points: points))
    }

    private static func largestTriangleArea(in points: [CGPoint]) -> CGFloat {
        guard let start = points.first,
              let furthest = points.max(by: {
                  hypot($0.x - start.x, $0.y - start.y) < hypot($1.x - start.x, $1.y - start.y)
              }) else { return 0 }

        // Absolute area accepts self-crossing paths, which use an even-odd fill.
        return points.dropFirst().reduce(CGFloat.zero) { largest, point in
            let area = abs((furthest.x - start.x) * (point.y - start.y)
                - (furthest.y - start.y) * (point.x - start.x)) / 2
            return max(largest, area)
        }
    }
}

import AppKit

struct Selection: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let rect: DisplayRect
    let shape: SelectionShape

    static let minimumDimension: CGFloat = 4

    static func normalizedRect(from start: DisplayPoint, to end: DisplayPoint) -> DisplayRect {
        DisplayRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y),
        )
    }

    /// A completed drag must be large enough to contain useful content.
    static func isValid(_ rect: DisplayRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.width >= self.minimumDimension
            && rect.height >= self.minimumDimension
    }
}

enum SelectionShape: Equatable, Sendable {
    case rectangle
    case freehand(points: [DisplayPoint])
}

enum SelectionEvent<Value> {
    case started
    case completed(Value)
    case cancelled
}

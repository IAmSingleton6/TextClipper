import AppKit

struct Selection: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    // Display-local AppKit points, with the origin at the bottom-left. Pixel
    // conversion is centralized in the capture layer.
    let rect: CGRect
    let shape: SelectionShape

    static let minimumDimension: CGFloat = 4

    static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func isValid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.width >= self.minimumDimension && rect.height >= self.minimumDimension
    }
}

enum SelectionShape: Equatable, Sendable {
    case rectangle
    case freehand(points: [CGPoint])
}

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
        guard points.count >= 3, let bounds = bounds(for: points), Selection.isValid(bounds),
              let first = points.first,
              let second = points.max(by: {
                  hypot($0.x - first.x, $0.y - first.y) < hypot($1.x - first.x, $1.y - first.y)
              }) else { return nil }
        // Reject clicks, straight strokes, and negligible enclosed areas. Use
        // absolute triangle area so self-crossing paths remain valid (even-odd fill).
        let area = points.dropFirst().reduce(CGFloat.zero) { largest, point in
            max(largest, abs((second.x - first.x) * (point.y - first.y)
                    - (second.y - first.y) * (point.x - first.x)) / 2)
        }
        guard area.isFinite, area >= 8 else { return nil }
        return SelectionGeometry(rect: bounds, shape: .freehand(points: points))
    }
}

struct SelectionDisplay {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect

    static func containing(_ point: CGPoint, in displays: [SelectionDisplay]) -> SelectionDisplay? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        // Half-open edges give adjacent displays one deterministic owner.
        return displays.first { display in
            let frame = display.frame
            return [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
                && frame.width > 0 && frame.height > 0
                && point.x >= frame.minX && point.x < frame.maxX
                && point.y >= frame.minY && point.y < frame.maxY
        }
    }

    static func atMouse() -> SelectionDisplay? {
        let point = NSEvent.mouseLocation
        let displays = NSScreen.screens.compactMap { screen -> SelectionDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return SelectionDisplay(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        return self.containing(point, in: displays)
    }
}

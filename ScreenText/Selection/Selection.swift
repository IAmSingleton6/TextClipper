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
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy { $0.isFinite }
            && rect.width >= minimumDimension && rect.height >= minimumDimension
    }
}

enum SelectionShape: Equatable, Sendable {
    case rectangle
    case ellipse
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
            return [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy { $0.isFinite }
                && frame.width > 0 && frame.height > 0
                && point.x >= frame.minX && point.x < frame.maxX
                && point.y >= frame.minY && point.y < frame.maxY
        }
    }

    static func atMouse() -> SelectionDisplay? {
        let point = NSEvent.mouseLocation
        let displays = NSScreen.screens.compactMap { screen -> SelectionDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return SelectionDisplay(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        return containing(point, in: displays)
    }
}

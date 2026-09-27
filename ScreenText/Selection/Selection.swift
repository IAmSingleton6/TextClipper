import AppKit

struct Selection: Equatable {
    let displayID: CGDirectDisplayID
    // Display-local AppKit points, with the origin at the bottom-left. Pixel
    // conversion belongs to the capture layer in Phase 6.
    let rect: CGRect
    let shape: SelectionShape

    static let minimumDimension: CGFloat = 4

    static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func isValid(_ rect: CGRect) -> Bool {
        rect.width >= minimumDimension && rect.height >= minimumDimension
    }
}

enum SelectionShape: Equatable {
    case rectangle
    case ellipse
}

struct SelectionDisplay {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect

    static func atMouse() -> SelectionDisplay? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return SelectionDisplay(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}

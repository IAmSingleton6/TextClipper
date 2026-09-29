import AppKit

struct SelectionDisplay {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect

    var hasValidFrame: Bool {
        [self.frame.minX, self.frame.minY, self.frame.maxX, self.frame.maxY].allSatisfy(\.isFinite)
            && self.frame.width > 0 && self.frame.height > 0
    }

    static func containing(_ point: CGPoint, in displays: [SelectionDisplay]) -> SelectionDisplay? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return displays.first { $0.contains(point) }
    }

    static func atMouse() -> SelectionDisplay? {
        let displays = NSScreen.screens.compactMap { screen -> SelectionDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return SelectionDisplay(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        return self.containing(NSEvent.mouseLocation, in: displays)
    }

    private func contains(_ point: CGPoint) -> Bool {
        guard self.hasValidFrame else { return false }
        // Half-open edges give adjacent displays one deterministic owner.
        return point.x >= self.frame.minX && point.x < self.frame.maxX
            && point.y >= self.frame.minY && point.y < self.frame.maxY
    }
}

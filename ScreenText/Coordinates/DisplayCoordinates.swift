import AppKit

enum DisplayCoordinates {
    /// AppKit window-local points start at bottom-left with Y up; the selection view is unflipped.
    @MainActor
    static func clampedPoint(from windowPoint: CGPoint, in view: NSView) -> DisplayPoint {
        let point = view.convert(windowPoint, from: nil)
        let bounds = view.bounds
        return DisplayPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY),
        )
    }
}

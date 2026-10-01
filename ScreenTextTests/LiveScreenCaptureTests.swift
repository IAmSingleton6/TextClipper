import AppKit
import ScreenCaptureKit
@testable import ScreenText
import Testing

@MainActor
struct LiveScreenCaptureTests {
    /// Explicit opt-in keeps ordinary tests independent of desktop permissions.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREEN_TEXT_LIVE_CAPTURE"] == "1",
                   "Requires the separate capture fixture and Screen Recording permission"))
    func `captures fixture at native scale with correct orientation and freehand mask`() async throws {
        try #require(CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess(),
                     "Enable ScreenText Screen Recording access in System Settings, then rerun this test")
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try #require(content.windows.contains { $0.title == "ScreenText Capture Test Fixture" })
        let rect = CGRect(x: screen.frame.width / 2 - 160, y: screen.frame.height / 2 - 120, width: 320, height: 240)
        let selection = Selection(
            displayID: number.uint32Value,
            rect: DisplayRect(displayLocalRect: rect),
            shape: .rectangle,
        )
        let service = ScreenCaptureService()
        let clipboardChanges = NSPasteboard.general.changeCount
        let image = try await service.capture(region: selection)
        #expect(image.width == Int(320 * screen.backingScaleFactor))
        #expect(image.height == Int(240 * screen.backingScaleFactor))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let top = try #require(bitmap.colorAt(x: image.width / 2, y: image.height / 4)?.usingColorSpace(.deviceRGB))
        let bottom = try #require(bitmap.colorAt(x: image.width / 2, y: image.height * 3 / 4)?
            .usingColorSpace(.deviceRGB))
        #expect(top.blueComponent > 0.9 && top.redComponent < 0.1)
        #expect(bottom.redComponent > 0.9 && bottom.blueComponent < 0.1)

        let freehand = try await service.capture(region: Selection(
            displayID: number.uint32Value,
            rect: DisplayRect(displayLocalRect: rect),
            shape: .freehand(points: [
                .init(x: rect.midX, y: rect.minY), .init(x: rect.maxX, y: rect.midY),
                .init(x: rect.midX, y: rect.maxY), .init(x: rect.minX, y: rect.midY),
            ]),
        ))
        let masked = NSBitmapImageRep(cgImage: freehand)
        #expect(freehand.width == image.width && freehand.height == image.height)
        #expect(try #require(masked.colorAt(x: 0, y: 0)).alphaComponent == 0)
        #expect(try #require(masked.colorAt(x: freehand.width / 2, y: freehand.height / 2)).alphaComponent > 0.99)
        #expect(NSPasteboard.general.changeCount == clipboardChanges)
        print(
            "Live capture verified: \(image.width) × \(image.height) pixels, \(screen.backingScaleFactor)× display scale; orientation and freehand mask correct.",
        )
    }
}

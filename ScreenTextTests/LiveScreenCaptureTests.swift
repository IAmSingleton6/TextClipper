import AppKit
import ScreenCaptureKit
@testable import ScreenText
import Testing

extension DesktopTests {
    @MainActor
    struct LiveScreenCaptureTests {
        @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREEN_TEXT_LIVE_CAPTURE"] == "1",
                       "Requires the separate capture fixture and Screen Recording permission"))
        func `live rectangle capture uses native scale and preserves vertical orientation`() async throws {
            // GIVEN
            let fixture = try await LiveCaptureFixture()

            // WHEN
            let image = try await ScreenCaptureService().capture(region: fixture.rectangle)

            // THEN
            #expect(image.width == Int(320 * fixture.scale))
            #expect(image.height == Int(240 * fixture.scale))
            let top = try fixture.color(in: image, x: image.width / 2, y: image.height / 4)
            let bottom = try fixture.color(in: image, x: image.width / 2, y: image.height * 3 / 4)
            #expect(top.blueComponent > 0.9)
            #expect(top.redComponent < 0.1)
            #expect(bottom.redComponent > 0.9)
            #expect(bottom.blueComponent < 0.1)
            #expect(NSPasteboard.general.changeCount == fixture.clipboardChanges)
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREEN_TEXT_LIVE_CAPTURE"] == "1",
                       "Requires the separate capture fixture and Screen Recording permission"))
        func `live freehand capture clears all corners and preserves its interior`() async throws {
            // GIVEN
            let fixture = try await LiveCaptureFixture()

            // WHEN
            let image = try await ScreenCaptureService().capture(region: fixture.diamond)

            // THEN
            #expect(image.width == Int(320 * fixture.scale))
            #expect(image.height == Int(240 * fixture.scale))
            for (x, y) in [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)] {
                #expect(try fixture.color(in: image, x: x, y: y).alphaComponent == 0)
            }
            #expect(try fixture.color(in: image, x: image.width / 2, y: image.height / 2).alphaComponent > 0.99)
            #expect(NSPasteboard.general.changeCount == fixture.clipboardChanges)
        }
    }
}

@MainActor
private struct LiveCaptureFixture {
    let rectangle: Selection
    let scale: CGFloat
    let clipboardChanges: Int
    var diamond: Selection {
        let rect = self.rectangle.rect
        return Selection(displayID: self.rectangle.displayID, rect: rect, shape: .freehand(points: [
            .init(x: rect.minX + rect.width / 2, y: rect.minY), .init(x: rect.maxX, y: rect.minY + rect.height / 2),
            .init(x: rect.minX + rect.width / 2, y: rect.maxY), .init(x: rect.minX, y: rect.minY + rect.height / 2),
        ]))
    }

    init() async throws {
        try #require(CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess(),
                     "Enable ScreenText Screen Recording access in System Settings, then rerun")
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let window = try #require(content.windows.first { $0.title == "ScreenText Capture Test Fixture" })
        let localRect = CGRect(
            x: screen.frame.width / 2 - 160,
            y: screen.frame.height / 2 - 120,
            width: 320,
            height: 240,
        )
        let globalRect = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let screenshotRect = CGRect(x: globalRect.minX, y: screen.frame.maxY - globalRect.maxY, width: 320, height: 240)
        try #require(
            abs(window.frame.minX - screenshotRect.minX) < 1 && abs(window.frame.minY - screenshotRect.minY) < 1,
            "The external fixture must cover the expected capture region on the first display",
        )
        self.rectangle = Selection(
            displayID: number.uint32Value,
            rect: DisplayRect(displayLocalRect: localRect),
            shape: .rectangle,
        )
        self.scale = screen.backingScaleFactor
        self.clipboardChanges = NSPasteboard.general.changeCount
    }

    func color(in image: CGImage, x: Int, y: Int) throws -> NSColor {
        try #require(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }
}

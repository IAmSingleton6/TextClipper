import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: Error, Equatable {
    case permissionDenied
    case displayNotFound
    case invalidRegion
    case captureFailed
}

protocol ScreenCapturing: Sendable {
    func capture(region: Selection) async throws -> CGImage
}

struct ScreenCaptureService: ScreenCapturing {
    func capture(region: Selection) async throws -> CGImage {
        try Task.checkCancellation()
        if !CGPreflightScreenCaptureAccess() {
            let granted = await MainActor.run { CGRequestScreenCaptureAccess() }
            guard granted else { throw ScreenCaptureError.permissionDenied }
        }
        try Task.checkCancellation()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if (error as NSError).domain == SCStreamErrorDomain,
               (error as NSError).code == SCStreamError.Code.userDeclined.rawValue
            {
                throw ScreenCaptureError.permissionDenied
            }
            throw ScreenCaptureError.captureFailed
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }
        // Exclude capture/feedback panels, including any retained compositor frame,
        // but keep ordinary app windows such as Settings in the screenshot.
        let capturableWindowIDs = await MainActor.run {
            Self.capturableWindowIDs(in: NSApp.windows)
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let ownWindows = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                && capturableWindowIDs.contains($0.windowID)
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: ownWindows)
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }
        let converter = DisplayCoordinateConverter()
        let pointSize = filter.contentRect.size
        let pixelSize = try converter.imageSize(displaySize: pointSize, pixelScale: CGFloat(filter.pointPixelScale))
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            if (error as NSError).domain == SCStreamErrorDomain,
               (error as NSError).code == SCStreamError.Code.userDeclined.rawValue
            {
                throw ScreenCaptureError.permissionDenied
            }
            throw ScreenCaptureError.captureFailed
        }
        try Task.checkCancellation()
        return try self.croppedImage(from: image, region: region, displaySize: pointSize)
    }

    @MainActor
    static func capturableWindowIDs(in windows: [NSWindow]) -> Set<CGWindowID> {
        Set(windows.compactMap { window -> CGWindowID? in
            guard !(window is NSPanel), !(window is SelectionWindow) else { return nil }
            return self.capturableWindowID(for: window.windowNumber)
        })
    }

    static func capturableWindowID(for number: Int) -> CGWindowID? {
        guard number > 0 else { return nil }
        return CGWindowID(exactly: number)
    }

    /// Shared with offline image tests so the exact capture crop/mask path is verified.
    func croppedImage(from image: CGImage, region: Selection, displaySize: CGSize) throws -> CGImage {
        let converter = DisplayCoordinateConverter()
        let imageSize = CGSize(width: image.width, height: image.height)
        let cropRect = try converter.pixelRect(for: region.rect, displaySize: displaySize, imageSize: imageSize)
        guard let cropped = image.cropping(to: cropRect) else { throw ScreenCaptureError.captureFailed }
        switch region.shape {
        case .rectangle: return cropped
        case let .freehand(points):
            let localPoints = try converter.maskPoints(
                for: points,
                displaySize: displaySize,
                imageSize: imageSize,
                cropRect: cropRect,
            )
            return try ImageMasker().applyFreehandMask(to: cropped, points: localPoints)
        }
    }
}

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
               (error as NSError).code == SCStreamError.Code.userDeclined.rawValue {
                throw ScreenCaptureError.permissionDenied
            }
            throw ScreenCaptureError.captureFailed
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }
        // Exclusion also guards against a compositor frame retaining the just-hidden UI.
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        if #available(macOS 14.2, *) { filter.includeMenuBar = true }
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
               (error as NSError).code == SCStreamError.Code.userDeclined.rawValue {
                throw ScreenCaptureError.permissionDenied
            }
            throw ScreenCaptureError.captureFailed
        }
        try Task.checkCancellation()
        let cropRect = try converter.pixelRect(for: region.rect, displaySize: pointSize,
                                              imageSize: CGSize(width: image.width, height: image.height))
        guard let cropped = image.cropping(to: cropRect) else { throw ScreenCaptureError.captureFailed }
        return region.shape == .ellipse ? try ImageMasker().applyEllipseMask(to: cropped) : cropped
    }
}

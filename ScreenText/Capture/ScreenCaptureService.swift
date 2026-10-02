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
        try await self.requestPermissionIfNeeded()

        try Task.checkCancellation()
        let capturedDisplay = try await captureDisplay(for: region)

        try Task.checkCancellation()
        return try CaptureImageCropper().crop(
            capturedDisplay.image,
            to: region,
            displayPointSize: capturedDisplay.displayPointSize,
        )
    }

    private func requestPermissionIfNeeded() async throws {
        guard !CGPreflightScreenCaptureAccess() else { return }
        let granted = await MainActor.run { CGRequestScreenCaptureAccess() }
        guard granted else { throw ScreenCaptureError.permissionDenied }
    }

    private func captureDisplay(for region: Selection) async throws -> CapturedDisplay {
        let content = try await self.loadShareableContent()
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }

        let filter = await CaptureWindowFilter.makeContentFilter(for: display, from: content)
        let displayPointSize = filter.contentRect.size
        let configuration = try self.makeConfiguration(
            displayPointSize: displayPointSize,
            pixelScale: CGFloat(filter.pointPixelScale),
        )
        let image = try await captureImage(filter: filter, configuration: configuration)

        return CapturedDisplay(image: image, displayPointSize: displayPointSize)
    }

    private struct CapturedDisplay {
        let image: CGImage
        let displayPointSize: CGSize
    }

    private func loadShareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw self.captureError(for: error)
        }
    }

    private func makeConfiguration(displayPointSize: CGSize, pixelScale: CGFloat) throws -> SCStreamConfiguration {
        let imageSize = try ScreenshotSizing.requestedPixelSize(
            forDisplayPointSize: displayPointSize,
            pointPixelScale: pixelScale,
        )
        let configuration = SCStreamConfiguration()
        configuration.width = Int(imageSize.width)
        configuration.height = Int(imageSize.height)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }

    private func captureImage(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw self.captureError(for: error)
        }
    }

    private func captureError(for error: Error) -> ScreenCaptureError {
        let error = error as NSError
        if error.domain == SCStreamErrorDomain, error.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        return .captureFailed
    }
}

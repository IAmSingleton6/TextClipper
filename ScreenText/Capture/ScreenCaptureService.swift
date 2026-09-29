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

        let content = try await self.loadShareableContent()
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }

        let filter = await self.makeFilter(for: display, from: content)
        let displaySize = filter.contentRect.size
        let configuration = try self.makeConfiguration(
            displaySize: displaySize,
            pixelScale: CGFloat(filter.pointPixelScale),
        )
        let image = try await self.captureImage(filter: filter, configuration: configuration)

        try Task.checkCancellation()
        return try self.croppedImage(from: image, region: region, displaySize: displaySize)
    }

    private func requestPermissionIfNeeded() async throws {
        guard !CGPreflightScreenCaptureAccess() else { return }
        let granted = await MainActor.run { CGRequestScreenCaptureAccess() }
        guard granted else { throw ScreenCaptureError.permissionDenied }
    }

    private func loadShareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw self.captureError(for: error)
        }
    }

    private func makeFilter(for display: SCDisplay, from content: SCShareableContent) async -> SCContentFilter {
        // Hide our capture overlays while retaining ordinary app windows,
        // including Settings, in the screenshot.
        let includedWindowIDs = await MainActor.run {
            Self.capturableWindowIDs(in: NSApp.windows)
        }
        let processID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == processID }
        let includedOwnWindows = content.windows.filter {
            $0.owningApplication?.processID == processID && includedWindowIDs.contains($0.windowID)
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: includedOwnWindows,
        )
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }
        return filter
    }

    private func makeConfiguration(displaySize: CGSize, pixelScale: CGFloat) throws -> SCStreamConfiguration {
        let imageSize = try DisplayCoordinateConverter().imageSize(
            displaySize: displaySize,
            pixelScale: pixelScale,
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

    /// Shared with offline image tests so the capture crop and mask path is verified.
    func croppedImage(from image: CGImage, region: Selection, displaySize: CGSize) throws -> CGImage {
        let converter = DisplayCoordinateConverter()
        let imageSize = CGSize(width: image.width, height: image.height)
        let cropRect = try converter.pixelRect(
            for: region.rect,
            displaySize: displaySize,
            imageSize: imageSize,
        )
        guard let cropped = image.cropping(to: cropRect) else {
            throw ScreenCaptureError.captureFailed
        }

        switch region.shape {
        case .rectangle:
            return cropped
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

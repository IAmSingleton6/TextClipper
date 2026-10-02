import CoreGraphics

/// Calculates the whole-display pixel size requested from ScreenCaptureKit.
enum ScreenshotSizing {
    static func requestedPixelSize(forDisplayPointSize displaySize: CGSize, pointPixelScale: CGFloat) throws -> CGSize {
        guard
            displaySize.width.isFinite, displaySize.height.isFinite,
            displaySize.width > 0, displaySize.height > 0,
            pointPixelScale.isFinite, pointPixelScale > 0
        else {
            throw ScreenCaptureError.invalidRegion
        }

        let width = displaySize.width * pointPixelScale
        let height = displaySize.height * pointPixelScale
        guard width < CGFloat(Int.max), height < CGFloat(Int.max) else {
            throw ScreenCaptureError.invalidRegion
        }

        let pixelSize = CGSize(width: ceil(width), height: ceil(height))
        guard pixelSize.width >= 1, pixelSize.height >= 1 else {
            throw ScreenCaptureError.invalidRegion
        }

        return pixelSize
    }
}

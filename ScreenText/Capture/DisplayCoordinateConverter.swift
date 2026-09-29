import CoreGraphics

struct DisplayCoordinateConverter {
    /// Selection coordinates start at the display's bottom-left corner, while
    /// CGImage crop coordinates start at the top-left corner.
    func pixelRect(for rect: CGRect, displaySize: CGSize, imageSize: CGSize) throws -> CGRect {
        guard self.isFinite(rect), rect.width > 0, rect.height > 0,
              self.isValidSize(displaySize), self.isValidSize(imageSize)
        else {
            throw ScreenCaptureError.invalidRegion
        }

        let displayBounds = CGRect(origin: .zero, size: displaySize)
        let selection = rect.intersection(displayBounds)
        guard !selection.isNull, !selection.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }

        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else {
            throw ScreenCaptureError.invalidRegion
        }

        // Round outward to include every pixel touched by a fractional edge.
        let left = floor(selection.minX * scaleX)
        let right = ceil(selection.maxX * scaleX)
        let top = floor((displaySize.height - selection.maxY) * scaleY)
        let bottom = ceil((displaySize.height - selection.minY) * scaleY)
        guard [left, right, top, bottom].allSatisfy(\.isFinite) else {
            throw ScreenCaptureError.invalidRegion
        }

        let pixelBounds = CGRect(origin: .zero, size: imageSize)
        let crop = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(pixelBounds)
        guard !crop.isNull, !crop.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }
        return crop
    }

    /// Convert display-local points to the cropped CGContext's bottom-left
    /// coordinates. The CGImage crop rectangle itself uses a top-left origin.
    func maskPoints(
        for points: [CGPoint],
        displaySize: CGSize,
        imageSize: CGSize,
        cropRect: CGRect,
    ) throws -> [CGPoint] {
        guard self.isValidSize(displaySize), self.isValidSize(imageSize),
              self.isFinite(cropRect), !cropRect.isEmpty
        else {
            throw ScreenCaptureError.invalidRegion
        }

        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        let cropBottom = imageSize.height - cropRect.maxY

        return try points.map { point in
            let converted = CGPoint(
                x: point.x * scaleX - cropRect.minX,
                y: point.y * scaleY - cropBottom,
            )
            guard point.x.isFinite, point.y.isFinite,
                  converted.x.isFinite, converted.y.isFinite
            else {
                throw ScreenCaptureError.invalidRegion
            }
            return converted
        }
    }

    func imageSize(displaySize: CGSize, pixelScale: CGFloat) throws -> CGSize {
        guard self.isValidSize(displaySize), pixelScale.isFinite, pixelScale > 0 else {
            throw ScreenCaptureError.invalidRegion
        }

        let width = displaySize.width * pixelScale
        let height = displaySize.height * pixelScale
        guard width < CGFloat(Int.max), height < CGFloat(Int.max) else {
            throw ScreenCaptureError.invalidRegion
        }

        let imageSize = CGSize(width: ceil(width), height: ceil(height))
        guard imageSize.width >= 1, imageSize.height >= 1 else {
            throw ScreenCaptureError.invalidRegion
        }
        return imageSize
    }

    private func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private func isFinite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
    }
}

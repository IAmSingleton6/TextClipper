import CoreGraphics

struct DisplayCoordinateConverter {
    // Selection coordinates are display-local and bottom-left based. CGImage
    // crops use a top-left origin. Round outward so fractional edge pixels stay.
    func pixelRect(for rect: CGRect, displaySize: CGSize, imageSize: CGSize) throws -> CGRect {
        let values = [rect.origin.x, rect.origin.y, rect.width, rect.height, rect.maxX, rect.maxY,
                      displaySize.width, displaySize.height, imageSize.width, imageSize.height]
        guard values.allSatisfy({ $0.isFinite }),
              displaySize.width > 0, displaySize.height > 0,
              imageSize.width > 0, imageSize.height > 0,
              rect.width > 0, rect.height > 0 else { throw ScreenCaptureError.invalidRegion }
        let clipped = rect.intersection(CGRect(origin: .zero, size: displaySize))
        guard !clipped.isNull, !clipped.isEmpty else { throw ScreenCaptureError.invalidRegion }
        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else {
            throw ScreenCaptureError.invalidRegion
        }
        let left = floor(clipped.minX * scaleX)
        let top = floor((displaySize.height - clipped.maxY) * scaleY)
        let right = ceil(clipped.maxX * scaleX)
        let bottom = ceil((displaySize.height - clipped.minY) * scaleY)
        guard [left, top, right, bottom].allSatisfy({ $0.isFinite }) else { throw ScreenCaptureError.invalidRegion }
        let result = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard !result.isNull, !result.isEmpty else { throw ScreenCaptureError.invalidRegion }
        return result
    }

    func imageSize(displaySize: CGSize, pixelScale: CGFloat) throws -> CGSize {
        guard displaySize.width.isFinite, displaySize.height.isFinite, pixelScale.isFinite,
              displaySize.width > 0, displaySize.height > 0, pixelScale > 0,
              displaySize.width * pixelScale < CGFloat(Int.max),
              displaySize.height * pixelScale < CGFloat(Int.max) else {
            throw ScreenCaptureError.invalidRegion
        }
        let size = CGSize(width: ceil(displaySize.width * pixelScale), height: ceil(displaySize.height * pixelScale))
        guard size.width >= 1, size.height >= 1 else { throw ScreenCaptureError.invalidRegion }
        return size
    }
}

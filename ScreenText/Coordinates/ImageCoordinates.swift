import CoreGraphics

enum ImageCoordinates {
    static func toPixelRect(
        from displayRect: DisplayRect,
        displaySize: CGSize,
        imageSize: CGSize,
    ) throws -> ImagePixelRect {
        let scale = try self.displayToImageScale(displaySize: displaySize, imageSize: imageSize)
        let visibleSelection = try self.clipDisplayRect(displayRect, displaySize: displaySize)
        let roundedPixelRect = try self.makeRoundedPixelRect(
            from: visibleSelection,
            displayPointHeight: displaySize.height,
            scale: scale,
        )
        return try self.clipPixelRect(roundedPixelRect, imageSize: imageSize)
    }

    static func toCroppedPoints(
        from displayPoints: [DisplayPoint],
        cropRect: ImagePixelRect,
        displaySize: CGSize,
        imageSize: CGSize,
    ) throws -> [CroppedImagePixelPoint] {
        let scale = try self.displayToImageScale(displaySize: displaySize, imageSize: imageSize)
        guard self.isFinite(cropRect.cgImageCropRect), !cropRect.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }

        let cropBottom = imageSize.height - cropRect.maxY
        return try displayPoints.map { point in
            guard point.x.isFinite, point.y.isFinite else {
                throw ScreenCaptureError.invalidRegion
            }
            let localPoint = CroppedImagePixelPoint(
                x: point.x * scale.x - cropRect.minX,
                y: point.y * scale.y - cropBottom,
            )
            guard localPoint.x.isFinite, localPoint.y.isFinite else {
                throw ScreenCaptureError.invalidRegion
            }
            return localPoint
        }
    }

    private static func displayToImageScale(
        displaySize: CGSize,
        imageSize: CGSize,
    ) throws -> PixelScale {
        guard self.isValidSize(displaySize), self.isValidSize(imageSize) else {
            throw ScreenCaptureError.invalidRegion
        }
        let scale = PixelScale(
            x: imageSize.width / displaySize.width,
            y: imageSize.height / displaySize.height,
        )
        guard scale.x.isFinite, scale.y.isFinite, scale.x > 0, scale.y > 0 else {
            throw ScreenCaptureError.invalidRegion
        }
        return scale
    }

    private static func clipDisplayRect(
        _ selection: DisplayRect,
        displaySize: CGSize,
    ) throws -> DisplayRect {
        guard self.isFinite(selection.displayLocalRect), selection.width > 0, selection.height > 0 else {
            throw ScreenCaptureError.invalidRegion
        }
        let displayBounds = CGRect(origin: .zero, size: displaySize)
        let visibleSelection = selection.displayLocalRect.intersection(displayBounds)
        guard !visibleSelection.isNull, !visibleSelection.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }

        return DisplayRect(displayLocalRect: visibleSelection)
    }

    private static func makeRoundedPixelRect(
        from displayRect: DisplayRect,
        displayPointHeight: CGFloat,
        scale: PixelScale,
    ) throws -> ImagePixelRect {
        let left = floor(displayRect.minX * scale.x)
        let right = ceil(displayRect.maxX * scale.x)
        let top = floor((displayPointHeight - displayRect.maxY) * scale.y)
        let bottom = ceil((displayPointHeight - displayRect.minY) * scale.y)
        guard [left, right, top, bottom].allSatisfy(\.isFinite) else {
            throw ScreenCaptureError.invalidRegion
        }

        return ImagePixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func clipPixelRect(
        _ crop: ImagePixelRect,
        imageSize: CGSize,
    ) throws -> ImagePixelRect {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let visibleCrop = crop.cgImageCropRect.intersection(imageBounds)
        guard !visibleCrop.isNull, !visibleCrop.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }

        return ImagePixelRect(cgImageCropRect: visibleCrop)
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
    }

    private struct PixelScale {
        let x: CGFloat
        let y: CGFloat
    }
}

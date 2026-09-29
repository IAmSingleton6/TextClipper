import CoreGraphics

/// Maps display-local selection points into an actual screenshot's pixels.
/// DisplayRect -> ImageRect
enum SelectionCoordinates {
    static func displayRectToImagePixelRect(
        _ displayRect: CGRect,
        displayPointSize: CGSize,
        imagePixelSize: CGSize,
    ) throws -> CGRect {
        let scale = try self.pixelsPerDisplayPoint(displayPointSize: displayPointSize, imagePixelSize: imagePixelSize)
        let visibleSelection = try self.selectionClippedToDisplay(displayRect, displayPointSize: displayPointSize)
        let roundedCrop = try self.imagePixelRect(
            for: visibleSelection,
            displayPointHeight: displayPointSize.height,
            scale: scale,
        )

        return try self.cropClippedToImage(roundedCrop, imagePixelSize: imagePixelSize)
    }

    /// Converts display points into the cropped image's bottom-left-origin coordinate system
    static func displayPointsToCroppedImagePoints(
        _ displayPoints: [CGPoint],
        imageCropRect: CGRect,
        displayPointSize: CGSize,
        imagePixelSize: CGSize,
    ) throws -> [CGPoint] {
        let scale = try self.pixelsPerDisplayPoint(displayPointSize: displayPointSize, imagePixelSize: imagePixelSize)
        guard self.isFinite(imageCropRect), !imageCropRect.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }

        // The image crop uses a top-left origin, while CGContext uses bottom-left.
        let cropBottom = imagePixelSize.height - imageCropRect.maxY
        return try displayPoints.map { point in
            guard point.x.isFinite, point.y.isFinite else {
                throw ScreenCaptureError.invalidRegion
            }

            let localPoint = CGPoint(
                x: point.x * scale.x - imageCropRect.minX,
                y: point.y * scale.y - cropBottom,
            )
            guard localPoint.x.isFinite, localPoint.y.isFinite else {
                throw ScreenCaptureError.invalidRegion
            }
            return localPoint
        }
    }

    private static func pixelsPerDisplayPoint(
        displayPointSize: CGSize,
        imagePixelSize: CGSize,
    ) throws -> PixelScale {
        guard self.isValidSize(displayPointSize), self.isValidSize(imagePixelSize) else {
            throw ScreenCaptureError.invalidRegion
        }

        let scale = PixelScale(
            x: imagePixelSize.width / displayPointSize.width,
            y: imagePixelSize.height / displayPointSize.height,
        )
        guard scale.x.isFinite, scale.y.isFinite, scale.x > 0, scale.y > 0 else {
            throw ScreenCaptureError.invalidRegion
        }

        return scale
    }

    private static func selectionClippedToDisplay(
        _ selection: CGRect,
        displayPointSize: CGSize,
    ) throws -> CGRect {
        guard self.isFinite(selection), selection.width > 0, selection.height > 0 else {
            throw ScreenCaptureError.invalidRegion
        }

        let displayBounds = CGRect(origin: .zero, size: displayPointSize)
        let visibleSelection = selection.intersection(displayBounds)
        guard !visibleSelection.isNull, !visibleSelection.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }
        return visibleSelection
    }

    private static func imagePixelRect(
        for selection: CGRect,
        displayPointHeight: CGFloat,
        scale: PixelScale,
    ) throws -> CGRect {
        // Flip the vertical axis while converting the visible selection to pixels.
        let left = floor(selection.minX * scale.x)
        let right = ceil(selection.maxX * scale.x)
        let top = floor((displayPointHeight - selection.maxY) * scale.y)
        let bottom = ceil((displayPointHeight - selection.minY) * scale.y)
        guard [left, right, top, bottom].allSatisfy(\.isFinite) else {
            throw ScreenCaptureError.invalidRegion
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func cropClippedToImage(
        _ crop: CGRect,
        imagePixelSize: CGSize,
    ) throws -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: imagePixelSize)
        let visibleCrop = crop.intersection(imageBounds)
        guard !visibleCrop.isNull, !visibleCrop.isEmpty else {
            throw ScreenCaptureError.invalidRegion
        }
        return visibleCrop
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

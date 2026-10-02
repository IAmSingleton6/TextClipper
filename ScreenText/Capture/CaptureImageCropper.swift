import CoreGraphics

/// Turns a full-display screenshot into the selected image, with an optional
/// freehand mask. This also works with offline images in capture tests.
struct CaptureImageCropper {
    func crop(_ image: CGImage, to selection: Selection, displayPointSize: CGSize) throws -> CGImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageCropRect = try ImageCoordinates.toPixelRect(
            from: selection.rect,
            displaySize: displayPointSize,
            imageSize: imageSize,
        )
        guard let croppedImage = image.cropping(to: imageCropRect.cgImageCropRect) else {
            throw ScreenCaptureError.captureFailed
        }

        switch selection.shape {
        case .rectangle:
            return croppedImage
        case let .freehand(points):
            let maskPoints = try ImageCoordinates.toCroppedPoints(
                from: points,
                cropRect: imageCropRect,
                displaySize: displayPointSize,
                imageSize: imageSize,
            )
            return try ImageMasker().applyFreehandMask(to: croppedImage, points: maskPoints)
        }
    }
}

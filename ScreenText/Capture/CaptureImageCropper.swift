import CoreGraphics

/// Turns a full-display screenshot into the selected image, with an optional
/// freehand mask. This also works with offline images in capture tests.
struct CaptureImageCropper {
    func crop(_ image: CGImage, to selection: Selection, displaySize: CGSize) throws -> CGImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageCropRect = try SelectionCoordinates.displayRectToImagePixelRect(
            selection.rect,
            displayPointSize: displaySize,
            imagePixelSize: imageSize,
        )
        guard let croppedImage = image.cropping(to: imageCropRect) else {
            throw ScreenCaptureError.captureFailed
        }

        switch selection.shape {
        case .rectangle:
            return croppedImage
        case let .freehand(points):
            let maskPoints = try SelectionCoordinates.displayPointsToCroppedImagePoints(
                points,
                imageCropRect: imageCropRect,
                displayPointSize: displaySize,
                imagePixelSize: imageSize,
            )
            return try ImageMasker().applyFreehandMask(to: croppedImage, points: maskPoints)
        }
    }
}

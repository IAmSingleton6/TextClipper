import CoreGraphics

struct ImageMasker {
    enum MaskError: Error {
        case imageProcessingFailed
    }

    // The input is already cropped to the selection's pixel bounds. Preserve
    // those dimensions and clear the corners before the image reaches OCR.
    func applyEllipseMask(to image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw MaskError.imageProcessingFailed }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.clear(bounds)
        context.addEllipse(in: bounds)
        context.clip()
        context.draw(image, in: bounds)
        guard let masked = context.makeImage() else { throw MaskError.imageProcessingFailed }
        return masked
    }
}

import CoreGraphics

struct ImageMasker {
    enum MaskError: Error {
        case imageProcessingFailed
    }

    /// Clears pixels outside the freehand boundary before the image reaches OCR.
    func applyFreehandMask(to image: CGImage, points: [CroppedImagePixelPoint]) throws -> CGImage {
        guard
            points.count >= 3,
            points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else {
            throw MaskError.imageProcessingFailed
        }

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue,
        ) else {
            throw MaskError.imageProcessingFailed
        }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.clear(bounds)

        let path = CGMutablePath()
        path.addLines(between: points.map(\.maskContextPoint))
        path.closeSubpath()
        context.addPath(path)

        context.clip(using: .evenOdd)
        context.draw(image, in: bounds)

        guard let masked = context.makeImage() else { throw MaskError.imageProcessingFailed }
        return masked
    }
}

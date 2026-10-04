import CoreGraphics
import CoreText
import Foundation

/// Synthetic text exercises accurate detection and recognition without screen access.
enum OCRPreparationImage {
    static func make() -> CGImage? {
        let width = 320
        let height = 80

        guard let context = Self.createContext(
            width: width,
            height: height,
        ) else {
            return nil
        }

        Self.drawBackground(in: context, width: width, height: height)
        Self.drawText(in: context)

        return context.makeImage()
    }

    private static func createContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
    }

    private static func drawBackground(
        in context: CGContext,
        width: Int,
        height: Int,
    ) {
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func drawText(in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 32, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(gray: 0.0, alpha: 1.0),
        ]
        let text = NSAttributedString(
            string: "ScreenText 123",
            attributes: attributes,
        )
        let line = CTLineCreateWithAttributedString(text)

        context.textPosition = CGPoint(x: 16, y: 24)

        CTLineDraw(line, context)
    }
}

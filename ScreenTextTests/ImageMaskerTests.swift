import CoreGraphics
import Foundation
@testable import ScreenText
import Testing

struct ImageMaskerTests {
    @Test(arguments: [(100, 100), (160, 60), (60, 160), (101, 61)])
    func `masking clears corners while preserving interior pixels and the source image`(size: (Int, Int)) throws {
        // GIVEN
        let (width, height) = size
        let input = try TestImages.colored(width: width, height: height, topAlpha: 0.5)
        let original = try #require(input.dataProvider?.data) as Data
        let points: [CroppedImagePixelPoint] = [
            .init(x: CGFloat(width) / 2, y: 0), .init(x: CGFloat(width), y: CGFloat(height) / 2),
            .init(x: CGFloat(width) / 2, y: CGFloat(height)), .init(x: 0, y: CGFloat(height) / 2),
        ]

        // WHEN
        let output = try ImageMasker().applyFreehandMask(to: input, points: points)

        // THEN
        let pixels = try #require(output.dataProvider?.data) as Data
        #expect(output.width == width)
        #expect(output.height == height)
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            #expect(pixels[y * output.bytesPerRow + x * 4 + 3] == 0)
        }
        for y in [height / 4, height * 3 / 4] {
            let source = y * input.bytesPerRow + (width / 2) * 4
            let result = y * output.bytesPerRow + (width / 2) * 4
            #expect(Array(pixels[result ..< result + 4]) == Array(original[source ..< source + 4]))
        }
        #expect(try (#require(input.dataProvider?.data) as Data) == original)
    }

    @Test(arguments: [
        [CroppedImagePixelPoint](), [.init(x: 0, y: 0), .init(x: 10, y: 10)],
        [.init(x: 0, y: 0), .init(x: .nan, y: 10), .init(x: 10, y: 0)],
        [.init(x: 0, y: 0), .init(x: 10, y: .infinity), .init(x: 10, y: 0)],
    ])
    func `invalid polygon points report a mask failure`(points: [CroppedImagePixelPoint]) throws {
        let image = try TestImages.colored()
        #expect(throws: ImageMasker.MaskError.self) {
            try ImageMasker().applyFreehandMask(to: image, points: points)
        }
    }
}

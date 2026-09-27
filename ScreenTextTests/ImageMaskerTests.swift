import CoreGraphics
import Foundation
import Testing
@testable import ScreenText

struct ImageMaskerTests {
    @Test(arguments: [(100, 100), (160, 60), (60, 160), (101, 61)])
    func clearsCornersAndPreservesInteriorAndOrientation(size: (Int, Int)) throws {
        let (width, height) = size
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        let input = try #require(context.makeImage())
        let original = try #require(input.dataProvider?.data) as Data
        let output = try ImageMasker().applyFreehandMask(to: input, points: [
            .init(x: width / 2, y: 0), .init(x: width, y: height / 2),
            .init(x: width / 2, y: height), .init(x: 0, y: height / 2)
        ])
        let pixels = try #require(output.dataProvider?.data) as Data
        #expect(output.width == width)
        #expect(output.height == height)
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            #expect(pixels[y * output.bytesPerRow + x * 4 + 3] == 0)
        }
        for y in [height / 4, height * 3 / 4] {
            let source = y * input.bytesPerRow + (width / 2) * 4
            let result = y * output.bytesPerRow + (width / 2) * 4
            #expect(Array(pixels[result..<result + 4]) == Array(original[source..<source + 4]))
        }
        #expect((try #require(input.dataProvider?.data) as Data) == original)
    }
}

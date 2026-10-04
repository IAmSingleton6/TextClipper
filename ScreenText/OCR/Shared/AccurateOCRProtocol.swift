import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Wire protocol shared by AccurateOCRConnection and AccurateOCRHelper: PNG images and length-prefixed messages.
enum AccurateOCRProtocol {
    static func write(_ data: Data, to handle: FileHandle) throws {
        guard let count = UInt32(exactly: data.count) else { throw OCRError.recognitionFailed }
        let header = Data([24, 16, 8, 0].map { UInt8(truncatingIfNeeded: count >> $0) })
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
    }

    static func read(from handle: FileHandle) throws -> Data? {
        guard let header = try self.readExactly(4, from: handle) else { return nil }
        let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard let data = try self.readExactly(Int(count), from: handle) else { throw OCRError.recognitionFailed }
        return data
    }

    static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw OCRError.recognitionFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw OCRError.recognitionFailed }
        return data as Data
    }

    static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw OCRError.recognitionFailed }
        return image
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data? {
        var data = Data()
        while data.count < count {
            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else {
                if data.isEmpty {
                    return nil
                }
                throw OCRError.recognitionFailed
            }
            data.append(chunk)
        }
        return data
    }
}

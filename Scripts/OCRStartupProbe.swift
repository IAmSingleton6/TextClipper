import CoreGraphics
import CoreText
import Foundation
import Vision

/// Compile into a new output path for each cold run; do not delete Vision's caches.
/// Compare the default mode, --prime-fast, and --fast-only in separate fresh binaries.
@main
struct OCRStartupProbe {
    static func main() async throws {
        let image = try self.makeImage()
        #if PROCESS_PROBE
            try await self.measureSeparateProcess(image)
        #else
            try self.measureSameProcess(image)
        #endif
    }

    private static func measureSameProcess(_ image: CGImage) throws {
        let fast = VNRecognizeTextRequest()
        fast.recognitionLevel = .fast
        fast.usesLanguageCorrection = true
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)

        if CommandLine.arguments.contains("--prime-fast") {
            try self.measure(fast, image: image, label: "Fast before accurate startup")
        }
        let fastOnly = CommandLine.arguments.contains("--fast-only")
        if !fastOnly {
            // A dedicated queue rules out serialization by our Swift actors.
            DispatchQueue(label: "OCRStartupProbe.accurate", qos: .userInitiated).async {
                let accurate = VNRecognizeTextRequest()
                accurate.recognitionLevel = .accurate
                accurate.usesLanguageCorrection = true
                accurate.automaticallyDetectsLanguage = true
                started.signal()
                do {
                    try self.measure(accurate, image: image, label: "Accurate initialization")
                } catch {
                    print("Accurate initialization failed: \(error)")
                }
                finished.signal()
            }
            started.wait()
            Thread.sleep(forTimeInterval: 0.5)
        }
        for capture in 1 ... 3 {
            try self.measure(fast, image: image, label: "Fast capture \(capture)")
            Thread.sleep(forTimeInterval: 0.2)
        }
        if !fastOnly {
            finished.wait()
        }
    }

    #if PROCESS_PROBE
        private static func measureSeparateProcess(_ image: CGImage) async throws {
            let accurateRecognizer = AccurateOCR()
            let service = OCRService(
                accurateRecognizer: accurateRecognizer,
                fastRecognizer: VisionOCR(level: .fast),
                preparer: accurateRecognizer,
            )
            let started = ContinuousClock.now
            let preparation = Task { await service.prepare() }
            try await Task.sleep(for: .milliseconds(500))
            for capture in 1 ... 3 {
                let captured = ContinuousClock.now
                let text = try await service.recognizeText(from: image)
                print("Capture \(capture) during preparation: \(captured.duration(to: .now)); text: \(text)")
                try await Task.sleep(for: .milliseconds(200))
            }
            await preparation.value
            print("Helper preparation: \(started.duration(to: .now))")
            for capture in 1 ... 3 {
                let captured = ContinuousClock.now
                let text = try await service.recognizeText(from: image)
                print("Accurate capture \(capture) after preparation: \(captured.duration(to: .now)); text: \(text)")
            }
        }
    #endif

    private static func measure(_ request: VNRecognizeTextRequest, image: CGImage, label: String) throws {
        let started = ContinuousClock.now
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let elapsed = started.duration(to: .now)
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        print("\(label): \(elapsed); text: \(text)")
    }

    private static func makeImage() throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: 640, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { throw ProbeError.imageUnavailable }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 100))
        let text = NSAttributedString(string: "ScreenText startup test 123", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica" as CFString,
                32,
                nil,
            ),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        context.textPosition = CGPoint(x: 16, y: 32)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        guard let image = context.makeImage() else { throw ProbeError.imageUnavailable }
        return image
    }

    private enum ProbeError: Error { case imageUnavailable }
}

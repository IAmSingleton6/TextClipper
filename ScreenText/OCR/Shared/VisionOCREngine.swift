import CoreGraphics
import Vision

/// Synchronous Vision recognition shared by the app and its helper process.
/// Reuses a mutable request; callers must serialize access through an actor or a sequential loop.
struct VisionOCREngine {
    private let request: VNRecognizeTextRequest

    init(level: VNRequestTextRecognitionLevel) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = level == .accurate
        self.request = request
    }

    func recognizeText(from image: CGImage) throws -> String {
        try Task.checkCancellation()

        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([self.request])
        } catch {
            try Task.checkCancellation()
            throw OCRError.recognitionFailed
        }
        try Task.checkCancellation()

        let blocks = (self.request.results ?? []).compactMap { observation -> RecognizedTextBlock? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RecognizedTextBlock(
                text: text,
                bounds: VisionNormalizedRect(visionNormalizedRect: observation.boundingBox),
            )
        }

        return OCRTextProcessor().text(from: blocks)
    }
}

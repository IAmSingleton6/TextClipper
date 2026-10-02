import CoreGraphics
import Vision

enum OCRError: Error, Equatable {
    case recognitionFailed
}

protocol TextRecognizing: Sendable {
    func recognizeText(from image: CGImage) async throws -> String
}

struct OCRService: TextRecognizing {
    /// This nonisolated async service runs Vision away from the main actor.
    /// Requests and images live only for the duration of this operation.
    func recognizeText(from image: CGImage) async throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            try Task.checkCancellation()
            throw OCRError.recognitionFailed
        }
        try Task.checkCancellation()
        let blocks = (request.results ?? []).compactMap { observation -> RecognizedTextBlock? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RecognizedTextBlock(text: text, bounds: observation.boundingBox)
        }
        return OCRTextProcessor().text(from: blocks)
    }
}

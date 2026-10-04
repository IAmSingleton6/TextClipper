import CoreGraphics
import Vision

/// App-facing adapter that serializes synchronous Vision recognition in the app process.
/// The helper uses the same engine directly because its input loop already serializes requests.
actor VisionOCR: TextRecognizing {
    private let engine: VisionOCREngine

    init(level: VNRequestTextRecognitionLevel) {
        self.engine = VisionOCREngine(level: level)
    }

    func recognizeText(from image: CGImage) async throws -> String {
        try self.engine.recognizeText(from: image)
    }
}

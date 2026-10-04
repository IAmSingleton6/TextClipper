import CoreGraphics
import Vision

/// App-facing adapter that serializes synchronous Vision recognition in the app process.
/// The helper uses the same engine directly because its input loop already serializes requests.
actor VisionOCR: TextRecognizing {
    private let level: VNRequestTextRecognitionLevel
    private var engine: VisionOCREngine

    init(level: VNRequestTextRecognitionLevel) {
        self.level = level
        self.engine = VisionOCREngine(level: level)
    }

    func recognizeText(from image: CGImage) async throws -> String {
        let engine = self.engine
        do {
            let text = try await withTaskCancellationHandler {
                try engine.recognizeText(from: image)
            } onCancel: {
                engine.cancel()
            }
            try Task.checkCancellation()
            return text
        } catch {
            if Task.isCancelled {
                // A cancelled request must not be reused by the next capture.
                self.engine = VisionOCREngine(level: self.level)
            }
            throw error
        }
    }
}

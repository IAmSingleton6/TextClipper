enum CaptureProcessingResult {
    case textCopied(String)
    case noTextFound
}

@MainActor
protocol CaptureProcessing {
    func process(_ selection: Selection) async throws -> CaptureProcessingResult
}

@MainActor
struct CaptureProcessor: CaptureProcessing {
    private let captureService: any ScreenCapturing
    private let ocrService: any TextRecognizing
    private let clipboardService: any ClipboardWriting

    init(
        captureService: any ScreenCapturing,
        ocrService: any TextRecognizing,
        clipboardService: any ClipboardWriting,
    ) {
        self.captureService = captureService
        self.ocrService = ocrService
        self.clipboardService = clipboardService
    }

    func process(_ selection: Selection) async throws -> CaptureProcessingResult {
        try Task.checkCancellation()

        let image = try await self.captureService.capture(region: selection)
        try Task.checkCancellation()

        let text = try await self.ocrService.recognizeText(from: image)
        try Task.checkCancellation()

        guard try self.clipboardService.copy(text) else { return .noTextFound }
        return .textCopied(text)
    }
}

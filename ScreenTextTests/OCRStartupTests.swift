import CoreGraphics
@testable import ScreenText
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor
struct OCRStartupTests {
    @Test func `first capture finishes while accurate initialization is still pending`() async throws {
        let preparer = SuspendedOCRPreparer()
        let service = OCRService(
            accurateRecognizer: FixedTextRecognizer(text: "Accurate text"),
            fastRecognizer: FixedTextRecognizer(text: "Immediate text"),
            preparer: preparer,
        )

        // GIVEN
        let preparation = Task { await service.prepare() }
        try await preparer.waitUntilStarted()
        let image = try TestImages.colored()

        // WHEN
        let text = try await service.recognizeText(from: image)

        // THEN
        #expect(text == "Immediate text")
        try await preparer.finish()
        await preparation.value
    }

    @Test func `captures switch to accurate recognition after initialization completes`() async throws {
        let accurate = SuspendedTextRecognizer()
        let preparer = SuspendedOCRPreparer()
        let service = OCRService(
            accurateRecognizer: accurate, fastRecognizer: FixedTextRecognizer(text: "Fast text"), preparer: preparer,
        )
        let image = try TestImages.colored()

        // GIVEN
        let preparation = Task { await service.prepare() }
        try await preparer.waitUntilStarted()
        #expect(try await service.recognizeText(from: image) == "Fast text")
        try await preparer.finish()
        await preparation.value

        // WHEN
        let capture = Task { try await service.recognizeText(from: image) }
        try await accurate.waitUntilStarted()
        try await accurate.finish(.success("Accurate text"))

        // THEN
        #expect(try await capture.value == "Accurate text")
    }

    @Test func `failed preparation keeps fast capture available and can retry`() async throws {
        let accurate = SuspendedTextRecognizer()
        let preparer = SuspendedOCRPreparer()
        let service = OCRService(
            accurateRecognizer: accurate, fastRecognizer: FixedTextRecognizer(text: "Fast text"), preparer: preparer,
        )

        // GIVEN
        let preparation = Task { await service.prepare() }
        try await preparer.waitUntilStarted()
        try await preparer.finish(.failure(OCRError.recognitionFailed))
        await preparation.value

        // WHEN
        let image = try TestImages.colored()
        #expect(try await service.recognizeText(from: image) == "Fast text")
        try await preparer.waitUntilStarted()
        let retry = Task { await service.prepare() }
        try await preparer.finish()
        await retry.value

        // THEN
        let capture = Task { try await service.recognizeText(from: image) }
        try await accurate.waitUntilStarted()
        try await accurate.finish(.success("Accurate text"))
        #expect(try await capture.value == "Accurate text")
    }

    @Test func `cancelled fast capture cannot copy text when preparation finishes later`() async throws {
        let preparer = SuspendedOCRPreparer()
        let fast = SuspendedTextRecognizer()
        let service = OCRService(
            accurateRecognizer: FixedTextRecognizer(text: "Accurate text"),
            fastRecognizer: fast,
            preparer: preparer,
        )
        let preparation = Task { await service.prepare() }
        try await preparer.waitUntilStarted()
        let clipboard = TestClipboardWriter()
        let capture = CaptureFixture(ocrService: service, clipboardService: clipboard)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await fast.waitUntilStarted()

        // WHEN
        capture.triggerEscape()
        try await fast.finish(.success("Cancelled text"))
        try await preparer.finish()
        await preparation.value
        try await capture.waitForProcessingToReturn()

        // THEN
        #expect(capture.isIdle)
        #expect(capture.results.isEmpty)
        #expect(clipboard.attempts.isEmpty)
    }

    @Test func `accurate worker failure falls back for the same capture while preparation retries`() async throws {
        let accurate = SuspendedTextRecognizer()
        let preparer = SuspendedOCRPreparer()
        let service = OCRService(
            accurateRecognizer: accurate, fastRecognizer: FixedTextRecognizer(text: "Fast recovery"),
            preparer: preparer,
        )

        // GIVEN
        let preparation = Task { await service.prepare() }
        try await preparer.waitUntilStarted()
        try await preparer.finish()
        await preparation.value

        // WHEN
        let image = try TestImages.colored()
        let capture = Task { try await service.recognizeText(from: image) }
        try await accurate.waitUntilStarted()
        try await accurate.finish(.failure(OCRError.recognitionFailed))

        // THEN
        #expect(try await capture.value == "Fast recovery")
        try await preparer.waitUntilStarted()
        try await preparer.finish()
        await service.prepare()
    }

    @Test func `finishing preparation preserves the first capture and its clipboard text`() async throws {
        let preparer = SuspendedOCRPreparer()
        let service = OCRService(
            accurateRecognizer: FixedTextRecognizer(text: "Accurate text"),
            fastRecognizer: FixedTextRecognizer(text: "First text"),
            preparer: preparer,
        )
        let preparation = Task { await service.prepare() }
        try await preparer.waitUntilStarted()
        let clipboard = TestClipboardWriter()
        let capture = CaptureFixture(ocrService: service, clipboardService: clipboard)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await capture.waitForResult()
        #expect(clipboard.texts == ["First text"])

        // WHEN
        try await preparer.finish()
        await preparation.value

        // THEN
        #expect(capture.isIdle)
        #expect(capture.results.count == 1)
        #expect(clipboard.texts == ["First text"])
    }

    @Test func `cancelling launch preparation stops its worker and keeps fast captures available`() async throws {
        let preparer = SuspendedOCRPreparer()
        let service = OCRService(
            accurateRecognizer: FixedTextRecognizer(text: "Accurate text"),
            fastRecognizer: FixedTextRecognizer(text: "Fast text"),
            preparer: preparer,
        )

        // GIVEN
        let preparation = Task { await service.prepare() }
        try await preparer.waitUntilStarted()

        // WHEN
        preparation.cancel()
        await preparation.value
        try await preparer.waitUntilCancelled()
        let image = try TestImages.colored()

        // THEN: a new capture retries preparation without waiting for it.
        #expect(try await service.recognizeText(from: image) == "Fast text")
        try await preparer.waitUntilStarted()
        try await preparer.finish()
        await service.prepare()
    }
}

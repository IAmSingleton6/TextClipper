import CoreGraphics

protocol TextRecognizing: Sendable {
    func recognizeText(from image: CGImage) async throws -> String
}

/// Prepares an app recognition backend before OCRService starts using it for captures.
protocol OCRPreparing: Sendable {
    func prepare() async throws
}

/// Serves captures immediately while the accurate recognizer prepares separately.
actor OCRService: TextRecognizing {
    private let accurateRecognizer: any TextRecognizing
    private let fastRecognizer: any TextRecognizing
    private let preparer: any OCRPreparing
    private var preparationTask: Task<Void, Never>?
    private var isPrepared = false

    init(
        accurateRecognizer: any TextRecognizing,
        fastRecognizer: any TextRecognizing,
        preparer: any OCRPreparing,
    ) {
        self.accurateRecognizer = accurateRecognizer
        self.fastRecognizer = fastRecognizer
        self.preparer = preparer
    }

    func prepare() async {
        guard !Task.isCancelled else { return }
        guard let task = self.prepareAccurateRecognizerIfNeeded() else { return }

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func recognizeText(from image: CGImage) async throws -> String {
        try Task.checkCancellation()
        self.prepareAccurateRecognizerIfNeeded()
        let usesAccurateRecognition = self.isPrepared
        let recognizer = usesAccurateRecognition ? self.accurateRecognizer : self.fastRecognizer

        do {
            let text = try await recognizer.recognizeText(from: image)
            try Task.checkCancellation()
            return text
        } catch {
            guard usesAccurateRecognition else { throw error }

            self.isPrepared = false
            try Task.checkCancellation()
            self.prepareAccurateRecognizerIfNeeded()

            return try await self.recognizeFast(from: image)
        }
    }

    private func recognizeFast(from image: CGImage) async throws -> String {
        let text = try await fastRecognizer.recognizeText(from: image)
        try Task.checkCancellation()
        return text
    }

    @discardableResult
    private func prepareAccurateRecognizerIfNeeded() -> Task<Void, Never>? {
        guard !self.isPrepared else { return nil }
        if let preparationTask {
            return preparationTask
        }

        let preparer = self.preparer
        let task = Task { [weak self] in
            let prepared: Bool

            do {
                try await preparer.prepare()
                try Task.checkCancellation()
                prepared = true
            } catch {
                prepared = false
            }

            await self?.preparationFinished(prepared)
        }
        self.preparationTask = task
        return task
    }

    private func preparationFinished(_ prepared: Bool) {
        self.isPrepared = prepared
        self.preparationTask = nil
    }

    deinit { preparationTask?.cancel() }
}

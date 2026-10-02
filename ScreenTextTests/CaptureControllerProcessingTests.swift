@testable import ScreenText
import Testing

@MainActor
extension CaptureControllerTests {
    @Test(arguments: [boxSelection, freehandSelection])
    func `completed selections reach the processor unchanged`(selection: Selection) async throws {
        let processor = TestCaptureProcessor()
        let capture = CaptureFixture(
            initialMode: selection.shape == .rectangle ? .box : .freehand,
            processor: processor,
        )

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.completeSelection(selection)
        try await capture.waitForResult()

        // THEN
        #expect(processor.selections == [selection])
        #expect(capture.isIdle)
        #expect(capture.results.count == 1)
    }

    @Test(arguments: [boxSelection, freehandSelection])
    func `recognized text is delivered after capture UI returns to idle`(selection: Selection) async throws {
        let capture = CaptureFixture(
            initialMode: selection.shape == .rectangle ? .box : .freehand,
            onEvent: { capture, event in
                if case .textRecognized = event {
                    #expect(capture.isIdle)
                    #expect(!capture.toolbarIsVisible)
                    #expect(!capture.selectionIsVisible)
                    #expect(!capture.escape.isListening)
                    #expect(capture.activityChanges == [true, false])
                }
            },
        )

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.completeSelection(selection)
        try await capture.waitForResult()

        // THEN
        guard case let .textRecognized(text) = try #require(capture.results.first) else {
            Issue.record("Successful processing should deliver recognized text")
            return
        }
        #expect(text == "Recognized fixture")
        #expect(capture.results.count == 1)
        #expect(!capture.isActive)
    }

    @Test func `processor errors are delivered after capture returns to idle`() async throws {
        let processor = TestCaptureProcessor(outcome: .failure(OCRError.recognitionFailed))
        let capture = CaptureFixture(processor: processor, onEvent: { capture, event in
            if case .failed = event {
                #expect(capture.isIdle)
                #expect(!capture.toolbarIsVisible)
                #expect(!capture.selectionIsVisible)
                #expect(!capture.escape.isListening)
                #expect(capture.activityChanges == [true, false])
            }
        })

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.completeSelection()
        try await capture.waitForResult()

        // THEN
        guard case let .failed(error) = try #require(capture.results.first) else {
            Issue.record("A processor error should report capture failure")
            return
        }
        #expect(error as? OCRError == .recognitionFailed)
        #expect(capture.results.count == 1)
        #expect(capture.isIdle)
    }

    @Test func `an empty result is delivered after capture returns to idle`() async throws {
        let capture = CaptureFixture(processor: TestCaptureProcessor(), onEvent: { capture, event in
            if case .noTextFound = event {
                #expect(capture.isIdle)
                #expect(!capture.toolbarIsVisible)
                #expect(!capture.selectionIsVisible)
                #expect(!capture.escape.isListening)
            }
        })

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.completeSelection()
        try await capture.waitForResult()

        // THEN
        guard case .noTextFound = try #require(capture.results.first) else {
            Issue.record("An empty processing result should report no text found")
            return
        }
        #expect(capture.results.count == 1)
        #expect(capture.isIdle)
    }

    @Test func `completing selection removes capture UI while processing is pending`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.completeSelection()
        try await processor.waitUntilStarted()

        // THEN
        #expect(capture.state == .processing)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.escape.isListening)
        #expect(capture.escape.stops == 1)
        #expect(capture.activityChanges == [true])
        #expect(capture.results.isEmpty)
    }

    @Test(arguments: [CaptureState.toolbar, .selecting(.box)])
    func `Escape cancels capture before processing`(state: CaptureState) {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()
        if state == .selecting(.box) {
            capture.beginSelection()
        }

        // WHEN
        capture.triggerEscape()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.escape.isListening)
        #expect(capture.escape.starts == 1)
        #expect(capture.escape.stops == 1)
        #expect(capture.activityChanges == [true, false])
        #expect(capture.results.isEmpty)
    }

    @Test func `Escape listening resumes for the next session`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()
        capture.triggerEscape()

        // WHEN
        capture.start()

        // THEN
        #expect(capture.state == .toolbar)
        #expect(capture.escape.isListening)
        #expect(capture.escape.starts == 2)
        #expect(capture.escape.stops == 1)
    }

    @Test func `Escape has no effect while idle`() {
        let capture = CaptureFixture()

        // WHEN
        capture.triggerEscape()

        // THEN
        #expect(capture.isIdle)
        #expect(capture.events.isEmpty)
        #expect(capture.escape.starts == 0)
    }

    @Test func `Escape is unavailable during processing`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()

        // WHEN
        capture.triggerEscape()

        // THEN
        #expect(capture.state == .processing)
        #expect(!capture.escape.isListening)
        #expect(capture.escape.starts == 1)
        #expect(capture.escape.stops == 1)
        #expect(capture.results.isEmpty)
    }

    @Test func `processing locks the selected mode`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()

        // WHEN
        capture.requestMode(.freehand)

        // THEN
        #expect(capture.state == .processing)
        #expect(capture.selectedMode == .box)
        #expect(capture.savedMode == .box)
    }

    @Test func `starting during processing does not reopen capture UI`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()

        // WHEN
        capture.start()

        // THEN
        #expect(capture.state == .processing)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(capture.selections.prepareCount == 1)
        #expect(capture.escape.starts == 1)
        #expect(capture.escape.stops == 1)
        #expect(capture.activityChanges == [true])
        #expect(capture.results.isEmpty)
    }

    @Test(arguments: ProcessingOutcome.allCases)
    private func `cancelled processing discards late results and errors`(outcome: ProcessingOutcome) async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()

        // WHEN
        capture.cancel()
        try processor.finish(with: outcome.result)
        try await processor.waitUntilReturned()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.escape.isListening)
        #expect(processor.returnedWhileCancelled == [true])
        #expect(capture.activityChanges == [true, false])
        #expect(capture.results.isEmpty)
    }

    @Test func `toggling before processing starts discards its eventual result`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()

        // WHEN
        capture.toggle()
        try await processor.waitUntilStarted()
        try processor.finish(with: .success(.textCopied("Late text")))
        try await processor.waitUntilReturned()

        // THEN
        #expect(capture.isIdle)
        #expect(processor.returnedWhileCancelled == [true])
        #expect(capture.results.isEmpty)
        #expect(capture.activityChanges == [true, false])
    }

    @Test(arguments: ProcessingOutcome.allCases, [CaptureState.toolbar, .processing])
    private func `cancelled processing cannot disturb a newer session`(
        outcome: ProcessingOutcome,
        nextState: CaptureState,
    ) async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()
        capture.cancel()
        capture.start()
        if nextState == .processing {
            capture.beginSelection()
            capture.completeSelection()
            try await processor.waitUntilStarted()
        }

        // WHEN
        try processor.finish(with: outcome.result)
        try await processor.waitUntilReturned()

        // THEN
        #expect(capture.state == nextState)
        #expect(capture.activityChanges == [true, false, true])
        #expect(capture.results.isEmpty)
        #expect(processor.returnedWhileCancelled == [true])
        #expect(capture.toolbarIsVisible == (nextState == .toolbar))
        #expect(capture.selectionIsVisible == (nextState == .toolbar))
        #expect(capture.escape.isListening == (nextState == .toolbar))
    }

    @Test func `a new session delivers its own result after cancelled processing returns`() async throws {
        let processor = TestCaptureProcessor(suspends: true)
        let capture = CaptureFixture(processor: processor)

        // GIVEN
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()
        capture.cancel()
        capture.start()
        capture.beginSelection()
        capture.completeSelection()
        try await processor.waitUntilStarted()
        try processor.finish(with: .success(.textCopied("Old text")))
        try await processor.waitUntilReturned()

        // WHEN
        try processor.finish(with: .success(.textCopied("New text")))
        try await capture.waitForResult()

        // THEN
        guard case let .textRecognized(text) = try #require(capture.results.first) else {
            Issue.record("The new session should deliver its own result")
            return
        }
        #expect(text == "New text")
        #expect(capture.results.count == 1)
        #expect(capture.isIdle)
        #expect(capture.activityChanges == [true, false, true, false])
    }
}

private enum ProcessingOutcome: CaseIterable {
    case text, noText, failure

    var result: Result<CaptureProcessingResult, Error> {
        switch self {
        case .text: .success(.textCopied("Late text"))
        case .noText: .success(.noTextFound)
        case .failure: .failure(OCRError.recognitionFailed)
        }
    }
}

import Testing

@Suite(.timeLimit(.minutes(1)))
struct TestSignalTests {
    @Test func `signals arriving before their waiter are buffered`() async throws {
        let signal = TestSignal()
        signal.signal()
        signal.signal()

        try await signal.wait()
        try await signal.wait()
    }

    @Test func `a missing signal fails with its wait context`() async {
        let signal = TestSignal()
        await #expect(throws: TestWaitError.timedOut("capture result")) {
            try await signal.wait(for: "capture result", timeout: .milliseconds(20))
        }
    }

    @Test func `cancelling a pending waiter throws cancellation`() async {
        let signal = TestSignal()
        let waiter = Task { try await signal.wait() }
        await Task.yield()
        waiter.cancel()

        await #expect(throws: CancellationError.self) { try await waiter.value }
    }
}

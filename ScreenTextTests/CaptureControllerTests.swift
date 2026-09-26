import Testing
@testable import ScreenText

@Suite @MainActor
struct CaptureControllerTests {
    @Test func repeatedInvocationCancelsAndCanStartAgain() {
        let controller = CaptureController()
        var changes: [Bool] = []
        controller.onActivityChanged = { changes.append($0) }

        #expect(!controller.isActive)
        controller.toggle()
        #expect(controller.isActive)
        controller.toggle()
        #expect(!controller.isActive)
        controller.toggle()
        #expect(controller.isActive)
        #expect(changes == [true, false, true])
    }

    @Test func startAndCancelAreIdempotent() {
        let controller = CaptureController()
        var changes: [Bool] = []
        controller.onActivityChanged = { changes.append($0) }

        controller.cancel()
        controller.start()
        controller.start()
        controller.cancel()
        controller.cancel()
        #expect(!controller.isActive)
        #expect(changes == [true, false])
    }
}

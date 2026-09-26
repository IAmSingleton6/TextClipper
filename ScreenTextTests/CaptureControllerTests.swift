import Testing
@testable import ScreenText

@Suite @MainActor
struct CaptureControllerTests {
    @Test func repeatedInvocationCancelsAndCanStartAgain() {
        let controller = CaptureController(toolbar: TestCaptureToolbar())
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
        let controller = CaptureController(toolbar: TestCaptureToolbar())
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

    @Test func modeButtonsUpdateTheToolbarAndNewSessionsDefaultToBox() {
        let toolbar = TestCaptureToolbar()
        let controller = CaptureController(toolbar: toolbar)
        controller.selectMode(.circle)
        #expect(controller.selectedMode == .box)
        controller.start()
        #expect(toolbar.isVisible)
        #expect(toolbar.model?.mode == .box)
        toolbar.onModeSelected?(.circle)
        #expect(controller.selectedMode == .circle)
        #expect(toolbar.model?.mode == .circle)
        toolbar.onModeSelected?(.box)
        #expect(controller.selectedMode == .box)
        toolbar.onModeSelected?(.circle)
        toolbar.onCancel?()
        #expect(!controller.isActive)
        #expect(!toolbar.isVisible)
        controller.start()
        #expect(controller.selectedMode == .box)
        controller.toggle()
        #expect(!toolbar.isVisible)
        #expect(toolbar.showCount == 2)
        #expect(toolbar.hideCount == 2)
    }

    @Test func missingDisplayLeavesTheControllerIdle() {
        let toolbar = TestCaptureToolbar()
        toolbar.canShow = false
        let controller = CaptureController(toolbar: toolbar)
        var changes: [Bool] = []
        controller.onActivityChanged = { changes.append($0) }
        controller.start()
        #expect(!controller.isActive)
        #expect(changes.isEmpty)
    }
}

@MainActor
final class TestCaptureToolbar: CaptureToolbarPresenting {
    var canShow = true
    var isVisible = false
    var showCount = 0
    var hideCount = 0
    var model: CaptureToolbarModel?
    var onModeSelected: ((CaptureMode) -> Void)?
    var onCancel: (() -> Void)?

    func show(model: CaptureToolbarModel, onModeSelected: @escaping (CaptureMode) -> Void, onCancel: @escaping () -> Void) -> Bool {
        guard canShow else { return false }
        self.model = model
        self.onModeSelected = onModeSelected
        self.onCancel = onCancel
        isVisible = true
        showCount += 1
        return true
    }

    func hide() {
        isVisible = false
        hideCount += 1
        onModeSelected = nil
        onCancel = nil
    }
}

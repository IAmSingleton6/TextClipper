import CoreGraphics
import Testing
@testable import ScreenText

@Suite @MainActor
struct CaptureControllerTests {
    @Test func repeatedInvocationCancelsAndCanStartAgain() {
        let controller = CaptureController(captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(), selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
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
        let controller = CaptureController(captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(), selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
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
        let controller = CaptureController(captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
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
        let controller = CaptureController(captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
        var changes: [Bool] = []
        controller.onActivityChanged = { changes.append($0) }
        controller.start()
        #expect(!controller.isActive)
        #expect(changes.isEmpty)
    }
    @Test func selectionHidesToolbarAndDeliversResultAfterTeardown() async throws {
        let toolbar = TestCaptureToolbar()
        let selections = TestSelectionManager()
        let controller = CaptureController(captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: selections, displayProvider: { testDisplay })
        let selection = Selection(displayID: testDisplay.id, rect: .init(x: 25, y: 40, width: 100, height: 60), shape: .rectangle)
        var completed: CGImage?
        controller.onCaptureCompleted = {
            #expect(!toolbar.isVisible)
            #expect(!selections.isVisible)
            #expect(controller.state == .idle)
            completed = $0
        }
        controller.start()
        #expect(controller.state == .toolbar)
        selections.onStarted?()
        #expect(controller.state == .selecting(.box))
        #expect(!toolbar.isVisible)
        controller.selectMode(.circle)
        #expect(controller.selectedMode == .box)
        selections.onCompleted?(selection)
        #expect(controller.state == .processing)
        for _ in 0..<100 where completed == nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(completed?.width == 100)
        #expect(!controller.isActive)
    }

    @Test func circleDragLocksModeAndCompletesAfterTeardown() async throws {
        let toolbar = TestCaptureToolbar()
        let selections = TestSelectionManager()
        let controller = CaptureController(captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: selections, displayProvider: { testDisplay })
        let selection = Selection(displayID: testDisplay.id, rect: .init(x: 20, y: 30, width: 100, height: 60), shape: .ellipse)
        var completed: CGImage?
        controller.onCaptureCompleted = {
            #expect(controller.state == .idle)
            #expect(!toolbar.isVisible)
            #expect(!selections.isVisible)
            completed = $0
        }
        controller.start()
        controller.selectMode(.circle)
        selections.onStarted?()
        #expect(controller.state == .selecting(.circle))
        #expect(!toolbar.isVisible)
        controller.selectMode(.box)
        #expect(controller.selectedMode == .circle)
        selections.onCompleted?(selection)
        #expect(controller.state == .processing)
        for _ in 0..<100 where completed == nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(completed?.width == 100)
    }

    @Test func cancellingDragDoesNotDeliverSelection() {
        let selections = TestSelectionManager()
        let controller = CaptureController(captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(), selectionManager: selections, displayProvider: { testDisplay })
        var completed = false
        controller.onCaptureCompleted = { _ in completed = true }
        controller.start()
        selections.onStarted?()
        selections.onCancelled?()
        #expect(controller.state == .idle)
        #expect(!selections.isVisible)
        #expect(!completed)
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

    func show(display: SelectionDisplay, model: CaptureToolbarModel, onModeSelected: @escaping (CaptureMode) -> Void, onCancel: @escaping () -> Void) -> Bool {
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

private let testDisplay = SelectionDisplay(id: 1, frame: .init(x: -1440, y: 900, width: 1440, height: 900), visibleFrame: .init(x: -1440, y: 900, width: 1440, height: 875))

@MainActor
final class TestSelectionManager: SelectionManaging {
    var isVisible = false
    var onStarted: (() -> Void)?
    var onCompleted: ((Selection) -> Void)?
    var onCancelled: (() -> Void)?

    func prepare(display: SelectionDisplay, mode: CaptureMode, onStarted: @escaping () -> Void,
                 onCompleted: @escaping (Selection) -> Void, onCancelled: @escaping () -> Void) -> Bool {
        isVisible = true
        self.onStarted = onStarted
        self.onCompleted = onCompleted
        self.onCancelled = onCancelled
        return true
    }

    func setMode(_ mode: CaptureMode) {}

    func hide() {
        isVisible = false
        onStarted = nil
        onCompleted = nil
        onCancelled = nil
    }
}

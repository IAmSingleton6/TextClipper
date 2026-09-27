import CoreGraphics
@testable import ScreenText
import Testing

@MainActor
struct CaptureControllerTests {
    @Test func `repeated invocation cancels and can start again`() {
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(), captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(), selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
        var changes: [Bool] = []
        var events: [String] = []
        controller.onEvent = { event in
            switch event {
            case let .started(display):
                #expect(display.id == testDisplay.id)
                #expect(controller.state == .toolbar)
                events.append("started")
            case let .activityChanged(isActive):
                changes.append(isActive)
                events.append(isActive ? "active" : "inactive")
            default:
                Issue.record("Toggling capture must not deliver a result")
            }
        }

        #expect(!controller.isActive)
        controller.toggle()
        #expect(controller.isActive)
        controller.toggle()
        #expect(!controller.isActive)
        controller.toggle()
        #expect(controller.isActive)
        #expect(changes == [true, false, true])
        #expect(events == ["started", "active", "inactive", "started", "active"])
    }

    @Test func `start and cancel are idempotent`() {
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(), captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(), selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
        var changes: [Bool] = []
        controller.onEvent = { event in
            switch event {
            case let .activityChanged(isActive):
                changes.append(isActive)
            default: break
            }
        }

        controller.cancel()
        controller.start()
        controller.start()
        controller.cancel()
        controller.cancel()
        #expect(!controller.isActive)
        #expect(changes == [true, false])
    }

    @Test func `mode buttons update the toolbar and new sessions remember last mode`() {
        let toolbar = TestCaptureToolbar()
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(), captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
        controller.selectMode(.freehand)
        #expect(controller.selectedMode == .box)
        controller.start()
        #expect(toolbar.isVisible)
        #expect(toolbar.model?.mode == .box)
        toolbar.onAction?(.selectMode(.freehand))
        #expect(controller.selectedMode == .freehand)
        #expect(toolbar.model?.mode == .freehand)
        toolbar.onAction?(.selectMode(.box))
        #expect(controller.selectedMode == .box)
        toolbar.onAction?(.selectMode(.freehand))
        toolbar.onAction?(.cancel)
        #expect(!controller.isActive)
        #expect(!toolbar.isVisible)
        controller.start()
        #expect(controller.selectedMode == .freehand)
        toolbar.onAction?(.selectMode(.box))
        controller.toggle()
        #expect(!toolbar.isVisible)
        #expect(toolbar.showCount == 2)
        #expect(toolbar.hideCount == 2)
        controller.start()
        #expect(controller.selectedMode == .box)
        controller.cancel()
    }

    @Test func `missing display leaves the controller idle`() {
        let toolbar = TestCaptureToolbar()
        toolbar.canShow = false
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(), captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: TestSelectionManager(), displayProvider: { testDisplay })
        var changes: [Bool] = []
        controller.onEvent = { event in
            switch event {
            case let .activityChanged(isActive):
                changes.append(isActive)
            default: break
            }
        }
        controller.start()
        #expect(!controller.isActive)
        #expect(changes.isEmpty)
    }

    @Test func `selection hides toolbar and delivers result after teardown`() async throws {
        let toolbar = TestCaptureToolbar()
        let selections = TestSelectionManager()
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(), captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: selections, displayProvider: { testDisplay })
        let selection = Selection(displayID: testDisplay.id, rect: .init(x: 25, y: 40, width: 100, height: 60), shape: .rectangle)
        var completed: String?
        controller.onEvent = { event in
            switch event {
            case let .textRecognized(text):
                #expect(!toolbar.isVisible)
                #expect(!selections.isVisible)
                #expect(controller.state == .idle)
                completed = text
            default: break
            }
        }
        controller.start()
        #expect(controller.state == .toolbar)
        selections.onEvent?(.started)
        #expect(controller.state == .selecting(.box))
        #expect(!toolbar.isVisible)
        controller.selectMode(.freehand)
        #expect(controller.selectedMode == .box)
        selections.onEvent?(.completed(selection))
        #expect(controller.state == .processing)
        for _ in 0 ..< 100 where completed == nil {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(completed == "Recognized fixture")
        #expect(!controller.isActive)
    }

    @Test func `freehand drag locks mode and completes after teardown`() async throws {
        let toolbar = TestCaptureToolbar()
        let selections = TestSelectionManager()
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(), captureService: TestScreenCaptureService(), toolbar: toolbar, selectionManager: selections, displayProvider: { testDisplay })
        let selection = Selection(displayID: testDisplay.id, rect: .init(x: 20, y: 30, width: 100, height: 60), shape: .freehand(points: [.init(x: 20, y: 30), .init(x: 120, y: 30), .init(x: 120, y: 90)]))
        var completed: String?
        controller.onEvent = { event in
            switch event {
            case let .textRecognized(text):
                #expect(controller.state == .idle)
                #expect(!toolbar.isVisible)
                #expect(!selections.isVisible)
                completed = text
            default: break
            }
        }
        controller.start()
        controller.selectMode(.freehand)
        selections.onEvent?(.started)
        #expect(controller.state == .selecting(.freehand))
        #expect(!toolbar.isVisible)
        controller.selectMode(.box)
        #expect(controller.selectedMode == .freehand)
        selections.onEvent?(.completed(selection))
        #expect(controller.state == .processing)
        for _ in 0 ..< 100 where completed == nil {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(completed == "Recognized fixture")
    }

    @Test func `cancelling drag does not deliver selection`() {
        let selections = TestSelectionManager()
        let controller = CaptureController(clipboardService: TestClipboardWriter(), ocrService: TestTextRecognizer(), captureService: TestScreenCaptureService(), toolbar: TestCaptureToolbar(), selectionManager: selections, displayProvider: { testDisplay })
        var completed = false
        controller.onEvent = { event in
            switch event {
            case .textRecognized:
                completed = true
            default: break
            }
        }
        controller.start()
        selections.onEvent?(.started)
        selections.onEvent?(.cancelled)
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
    var onAction: ((CaptureToolbarAction) -> Void)?

    func show(display _: SelectionDisplay, model: CaptureToolbarModel, onAction: @escaping (CaptureToolbarAction) -> Void) -> Bool {
        guard self.canShow else { return false }
        self.model = model
        self.onAction = onAction
        self.isVisible = true
        self.showCount += 1
        return true
    }

    func hide() {
        self.isVisible = false
        self.hideCount += 1
        self.onAction = nil
    }
}

private let testDisplay = SelectionDisplay(id: 1, frame: .init(x: -1440, y: 900, width: 1440, height: 900), visibleFrame: .init(x: -1440, y: 900, width: 1440, height: 875))

@MainActor
final class TestSelectionManager: SelectionManaging {
    var isVisible = false
    var onEvent: ((SelectionEvent<Selection>) -> Void)?

    func prepare(display _: SelectionDisplay, mode _: CaptureMode, onEvent: @escaping (SelectionEvent<Selection>) -> Void) -> Bool {
        self.isVisible = true
        self.onEvent = onEvent
        return true
    }

    func setMode(_: CaptureMode) {}

    func hide() {
        self.isVisible = false
        self.onEvent = nil
    }
}

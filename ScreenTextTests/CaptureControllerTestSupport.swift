import CoreGraphics
@testable import ScreenText
import Testing

@MainActor
final class CaptureFixture {
    let toolbar = TestCaptureToolbar()
    let selections = TestSelectionManager()
    let escape = TestEscapeMonitor()
    var savedMode: CaptureMode
    private(set) var events: [CaptureEvent] = []
    private let display: SelectionDisplay?
    private let settings: SettingsStore?
    private let selectionManager: any SelectionManaging
    private let captureService: any ScreenCapturing
    private let ocrService: any TextRecognizing
    private let processor: ObservedCaptureProcessor
    private let onEvent: ((CaptureFixture, CaptureEvent) -> Void)?
    private let resultDelivered = TestSignal()
    private lazy var controller = CaptureController(
        modeProvider: { [weak self] in self?.settings?.lastSelectionMode ?? self?.savedMode ?? .box },
        saveMode: { [weak self] mode in
            self?.savedMode = mode
            self?.settings?.selectCaptureMode(mode)
        },
        toolbar: self.toolbar,
        selectionManager: self.selectionManager,
        displayProvider: { [weak self] in self?.display },
        escapeMonitor: self.escape,
        processor: self.processor,
        onEvent: { [weak self] in self?.record($0) },
    )

    init(
        initialMode: CaptureMode = .box,
        display: SelectionDisplay? = testDisplay,
        toolbarCanShow: Bool = true,
        toolbarCursorExclusionRect: ScreenRect? = nil,
        selectionCanPrepare: Bool = true,
        settings: SettingsStore? = nil,
        selectionManager: (any SelectionManaging)? = nil,
        captureService: any ScreenCapturing = TestScreenCaptureService(),
        ocrService: any TextRecognizing = TestTextRecognizer(),
        clipboardService: any ClipboardWriting = TestClipboardWriter(),
        processor: (any CaptureProcessing)? = nil,
        onEvent: ((CaptureFixture, CaptureEvent) -> Void)? = nil,
    ) {
        self.savedMode = settings?.lastSelectionMode ?? initialMode
        self.display = display
        self.settings = settings
        self.selectionManager = selectionManager ?? self.selections
        self.captureService = captureService
        self.ocrService = ocrService
        self.toolbar.canShow = toolbarCanShow
        self.toolbar.cursorExclusionRect = toolbarCursorExclusionRect
        self.selections.canPrepare = selectionCanPrepare
        self.processor = ObservedCaptureProcessor(base: processor ?? CaptureProcessor(
            captureService: captureService,
            ocrService: ocrService,
            clipboardService: clipboardService,
        ))
        self.onEvent = onEvent
    }

    var state: CaptureState {
        self.controller.state
    }

    var isActive: Bool {
        self.controller.isActive
    }

    var isIdle: Bool {
        self.state == .idle
    }

    var selectedMode: CaptureMode {
        self.controller.selectedMode
    }

    var selectionIsVisible: Bool {
        if let manager = self.selectionManager as? SelectionManager {
            return manager.window?.isVisible == true
        }
        return self.selections.isVisible
    }

    var toolbarIsVisible: Bool {
        self.toolbar.isVisible
    }

    var results: [CaptureEvent] {
        self.events.filter(\.isProcessingResult)
    }

    var activityChanges: [Bool] {
        self.events.compactMap {
            if case let .activityChanged(active) = $0 {
                active
            } else {
                nil
            }
        }
    }

    var lifecycleEvents: [String] {
        self.events.compactMap {
            switch $0 {
            case .started: "started"
            case let .activityChanged(active): active ? "active" : "inactive"
            default: nil
            }
        }
    }

    func start() {
        self.controller.start()
    }

    func cancel() {
        self.controller.cancel()
    }

    func toggle() {
        self.controller.toggle()
    }

    func selectMode(_ mode: CaptureMode) {
        self.toolbar.onAction?(.selectMode(mode))
    }

    func requestMode(_ mode: CaptureMode) {
        self.controller.selectMode(mode)
    }

    func cancelFromToolbar() {
        self.toolbar.onAction?(.cancel)
    }

    func beginSelection() {
        self.selections.beginSelection()
    }

    func cancelSelection() {
        self.selections.onEvent?(.cancelled)
    }

    func completeSelection(_ selection: Selection = boxSelection) {
        self.selections.completeSelection(selection)
    }

    func triggerEscape() {
        self.escape.trigger()
    }

    func waitForResult() async throws {
        try await self.resultDelivered.wait()
    }

    func waitForProcessingToReturn() async throws {
        try await self.processor.returned.wait()
    }

    private func record(_ event: CaptureEvent) {
        self.events.append(event)
        self.onEvent?(self, event)
        if event.isProcessingResult {
            self.resultDelivered.signal()
        }
    }

    isolated deinit {
        controller.cancel()
        (processor.base as? TestCaptureProcessor)?.releasePendingProcessing()
        if let service = captureService as? SuspendedCaptureService {
            Task { await service.releasePendingProcessing() }
        }
        if let service = ocrService as? SuspendedTextRecognizer {
            Task { await service.releasePendingProcessing() }
        }
    }
}

/// Both processor and controller run on MainActor: the controller handles this
/// return synchronously before the waiting test gets another actor turn.
@MainActor
private struct ObservedCaptureProcessor: CaptureProcessing {
    let base: any CaptureProcessing
    let returned = TestSignal()

    func process(_ selection: Selection) async throws -> CaptureProcessingResult {
        defer { self.returned.signal() }
        return try await self.base.process(selection)
    }
}

private extension CaptureEvent {
    var isProcessingResult: Bool {
        switch self {
        case .textRecognized, .noTextFound, .failed: true
        case .started, .activityChanged: false
        }
    }
}

@MainActor
final class TestEscapeMonitor: EscapeMonitoring {
    private(set) var starts = 0
    private(set) var stops = 0
    private var onEscape: (() -> Void)?
    var isListening: Bool {
        self.onEscape != nil
    }

    func start(onEscape: @escaping () -> Void) {
        self.starts += 1
        self.onEscape = onEscape
    }

    func stop() {
        self.stops += 1
        self.onEscape = nil
    }

    func trigger() {
        self.onEscape?()
    }
}

@MainActor
final class TestCaptureProcessor: CaptureProcessing {
    private(set) var selections: [Selection] = []
    private(set) var returnedWhileCancelled: [Bool] = []
    private let outcome: Result<CaptureProcessingResult, Error>
    private let suspends: Bool
    private var pending: [CheckedContinuation<CaptureProcessingResult, Error>] = []
    private let started = TestSignal()
    private let returned = TestSignal()

    init(outcome: Result<CaptureProcessingResult, Error> = .success(.noTextFound), suspends: Bool = false) {
        self.outcome = outcome
        self.suspends = suspends
    }

    func process(_ selection: Selection) async throws -> CaptureProcessingResult {
        self.selections.append(selection)
        self.started.signal()
        defer {
            self.returnedWhileCancelled.append(Task.isCancelled)
            // The processor and controller share MainActor. The controller handles the
            // return synchronously before a waiting test can resume on that actor.
            self.returned.signal()
        }
        if self.suspends {
            // Deliberately ignore cancellation so the controller must reject stale results.
            return try await withCheckedThrowingContinuation { self.pending.append($0) }
        }
        return try self.outcome.get()
    }

    func waitUntilStarted() async throws {
        try await self.started.wait()
    }

    func waitUntilReturned() async throws {
        try await self.returned.wait()
    }

    func finish(with outcome: Result<CaptureProcessingResult, Error> = .success(.noTextFound)) throws {
        let continuation = try #require(self.pending.first)
        self.pending.removeFirst()
        continuation.resume(with: outcome)
    }

    func releasePendingProcessing() {
        let continuations = self.pending
        self.pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
    }
}

let testDisplay = SelectionDisplay(
    id: 1,
    frame: .init(x: -1440, y: 900, width: 1440, height: 900),
    visibleFrame: .init(x: -1440, y: 900, width: 1440, height: 875),
)
let boxSelection = Selection(
    displayID: testDisplay.id,
    rect: .init(x: 25, y: 40, width: 100, height: 60),
    shape: .rectangle,
)
let freehandSelection = Selection(
    displayID: testDisplay.id,
    rect: .init(x: 20, y: 30, width: 100, height: 60),
    shape: .freehand(points: [.init(x: 20, y: 30), .init(x: 120, y: 30), .init(x: 120, y: 90)]),
)

/// These UI fakes are also used by the capture pipeline and settings suites.
@MainActor
final class TestCaptureToolbar: CaptureToolbarPresenting {
    var cursorExclusionRect: ScreenRect?
    var canShow = true
    var isVisible = false
    var showCount = 0
    var hideCount = 0
    var mode: CaptureMode?
    var onAction: ((CaptureToolbarAction) -> Void)?

    func show(
        display _: SelectionDisplay,
        mode: CaptureMode,
        onAction: @escaping (CaptureToolbarAction) -> Void,
    ) -> Bool {
        guard self.canShow else { return false }
        self.mode = mode
        self.onAction = onAction
        self.isVisible = true
        self.showCount += 1
        return true
    }

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
    }

    func hide() {
        self.isVisible = false
        self.hideCount += 1
        self.onAction = nil
    }
}

@MainActor
final class TestSelectionManager: SelectionManaging {
    var canPrepare = true
    var isVisible = false
    private(set) var prepareCount = 0
    private(set) var hideCount = 0
    private(set) var mode: CaptureMode?
    private(set) var cursorExclusionRect: ScreenRect?
    var onEvent: ((SelectionEvent<Selection>) -> Void)?

    func beginSelection() {
        self.onEvent?(.started)
    }

    func completeSelection(_ selection: Selection = boxSelection) {
        self.onEvent?(.completed(selection))
    }

    func prepare(
        display _: SelectionDisplay,
        mode: CaptureMode,
        onEvent: @escaping (SelectionEvent<Selection>) -> Void,
    ) -> Bool {
        self.prepareCount += 1
        guard self.canPrepare else { return false }
        self.mode = mode
        self.isVisible = true
        self.onEvent = onEvent
        return true
    }

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
    }

    func setCursorExclusionRect(_ rect: ScreenRect?) {
        self.cursorExclusionRect = rect
    }

    func hide() {
        self.hideCount += 1
        self.isVisible = false
        self.onEvent = nil
    }
}

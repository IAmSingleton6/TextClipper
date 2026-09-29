import CoreGraphics
import Foundation

enum CaptureState: Equatable {
    case idle
    case toolbar
    case selecting(CaptureMode)
    case processing
}

enum CaptureEvent {
    case started(SelectionDisplay)
    case activityChanged(Bool)
    case noTextFound
    case textRecognized(String)
    case failed(Error)
}

@MainActor
final class CaptureController {
    private(set) var state: CaptureState = .idle
    private(set) var selectedMode: CaptureMode = .box

    private let processor: any CaptureProcessing
    private let escapeMonitor: any EscapeMonitoring
    private let toolbar: any CaptureToolbarPresenting
    private let selectionManager: any SelectionManaging
    private let savedModeProvider: (() -> CaptureMode)?
    private let saveMode: (CaptureMode) -> Void
    private let displayProvider: () -> SelectionDisplay?
    private let onEvent: ((CaptureEvent) -> Void)?

    private var lastSelectedMode: CaptureMode?
    private var processingTask: Task<Void, Never>?
    private var sessionID = UUID()

    var isActive: Bool {
        self.state != .idle
    }

    init(
        clipboardService: any ClipboardWriting = ClipboardService(),
        ocrService: any TextRecognizing = OCRService(),
        captureService: any ScreenCapturing = ScreenCaptureService(),
        toolbar: any CaptureToolbarPresenting = CaptureToolbarWindow(),
        selectionManager: any SelectionManaging = SelectionManager(),
        displayProvider: @escaping () -> SelectionDisplay? = SelectionDisplay.atMouse,
        escapeMonitor: any EscapeMonitoring = EscapeMonitor(),
        savedModeProvider: (() -> CaptureMode)? = nil,
        saveMode: @escaping (CaptureMode) -> Void = { _ in },
        processor: (any CaptureProcessing)? = nil,
        onEvent: ((CaptureEvent) -> Void)? = nil,
    ) {
        self.processor = processor ?? CaptureProcessor(
            captureService: captureService,
            ocrService: ocrService,
            clipboardService: clipboardService,
        )
        self.escapeMonitor = escapeMonitor
        self.toolbar = toolbar
        self.selectionManager = selectionManager
        self.displayProvider = displayProvider
        self.savedModeProvider = savedModeProvider
        self.saveMode = saveMode
        self.onEvent = onEvent
    }

    func toggle() {
        if self.isActive {
            self.cancel()
        } else {
            self.start()
        }
    }

    func start() {
        guard !self.isActive, let display = self.displayProvider() else { return }

        let mode = self.resolveStartCaptureMode()

        guard self.selectionManager.prepare(
            display: display,
            mode: mode,
            onEvent: { [weak self] event in
                self?.handleSelectionEvent(event)
            },
        ) else {
            return
        }

        guard self.toolbar.show(
            display: display,
            mode: mode,
            onAction: { [weak self] action in
                self?.handleToolbarAction(action)
            },
        ) else {
            self.selectionManager.hide()
            return
        }

        self.selectedMode = mode
        self.enterToolbar(display: display)
    }

    private func resolveStartCaptureMode() -> CaptureMode {
        self.savedModeProvider?() ?? self.lastSelectedMode ?? .box
    }

    private func enterToolbar(display: SelectionDisplay) {
        self.selectionManager.setCursorExclusionRect(self.toolbar.cursorExclusionRect)
        self.state = .toolbar

        self.onEvent?(.started(display))
        self.onEvent?(.activityChanged(true))

        self.escapeMonitor.start { [weak self] in
            self?.cancel()
        }
    }

    private func handleSelectionEvent(_ event: SelectionEvent<Selection>) {
        switch event {
        case .started:
            self.selectionStarted()
        case let .completed(selection):
            self.selectionCompleted(selection)
        case .cancelled:
            self.cancel()
        }
    }

    private func handleToolbarAction(_ action: CaptureToolbarAction) {
        switch action {
        case let .selectMode(mode):
            self.selectMode(mode)
        case .cancel:
            self.cancel()
        }
    }

    func selectMode(_ mode: CaptureMode) {
        guard self.state == .toolbar else { return }

        self.selectedMode = mode
        self.lastSelectedMode = mode
        self.saveMode(mode)
        self.toolbar.setMode(mode)
        self.selectionManager.setMode(mode)
    }

    func cancel() {
        guard self.isActive else { return }

        self.sessionID = UUID()
        self.processingTask?.cancel()
        self.processingTask = nil
        self.hideSelectionUI()
        self.state = .idle
        self.onEvent?(.activityChanged(false))
    }

    private func hideSelectionUI() {
        self.escapeMonitor.stop()
        self.toolbar.hide()
        self.selectionManager.hide()
    }

    private func selectionStarted() {
        guard self.state == .toolbar else { return }

        self.state = .selecting(self.selectedMode)
        self.toolbar.hide()
        self.selectionManager.setCursorExclusionRect(nil)
    }

    private func selectionCompleted(_ selection: Selection) {
        guard case .selecting = self.state else { return }

        self.hideSelectionUI()
        self.state = .processing
        let id = UUID()
        self.sessionID = id
        let processor = self.processor

        self.processingTask = Task { [weak self] in
            do {
                let result = try await processor.process(selection)

                guard !Task.isCancelled, let self, sessionID == id else { return }

                self.cancel()
                switch result {
                case let .textCopied(text):
                    self.onEvent?(.textRecognized(text))
                case .noTextFound:
                    self.onEvent?(.noTextFound)
                }
            } catch {
                guard !Task.isCancelled, let self, sessionID == id else { return }

                self.cancel()
                self.onEvent?(.failed(error))
            }
        }
    }

    isolated deinit {
        escapeMonitor.stop()
        processingTask?.cancel()
    }
}

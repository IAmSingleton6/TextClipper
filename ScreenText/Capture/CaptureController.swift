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
    case processingChanged(Bool)
    case noTextFound
    case textRecognized(String)
    case failed(Error)
}

enum CaptureError: Error, Equatable {
    case timedOut
}

@MainActor
final class CaptureController {
    private(set) var state: CaptureState = .idle
    private(set) var selectedMode: CaptureMode

    private let processor: any CaptureProcessing
    private let escapeMonitor: any EscapeMonitoring
    private let toolbar: any CaptureToolbarPresenting
    private let selectionManager: any SelectionManaging
    private let modeProvider: () -> CaptureMode
    private let saveMode: (CaptureMode) -> Void
    private let displayProvider: () -> SelectionDisplay?
    private let processingTimeout: Duration
    private let onEvent: ((CaptureEvent) -> Void)?

    private var processingTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var sessionID = UUID()

    var isActive: Bool {
        self.state != .idle
    }

    init(
        modeProvider: @escaping () -> CaptureMode,
        saveMode: @escaping (CaptureMode) -> Void,
        processor: any CaptureProcessing,
        toolbar: any CaptureToolbarPresenting = CaptureToolbarWindow(),
        selectionManager: any SelectionManaging = SelectionManager(),
        displayProvider: @escaping () -> SelectionDisplay? = SelectionDisplay.atMouse,
        escapeMonitor: any EscapeMonitoring = EscapeMonitor(),
        processingTimeout: Duration = .seconds(15),
        onEvent: ((CaptureEvent) -> Void)? = nil,
    ) {
        self.selectedMode = modeProvider()
        self.processor = processor
        self.escapeMonitor = escapeMonitor
        self.toolbar = toolbar
        self.selectionManager = selectionManager
        self.displayProvider = displayProvider
        self.processingTimeout = processingTimeout
        self.modeProvider = modeProvider
        self.saveMode = saveMode
        self.onEvent = onEvent
    }

    func toggle() {
        switch self.state {
        case .idle:
            self.start()
        case .toolbar, .selecting:
            self.cancel()
        case .processing:
            // A cold Vision request can take time to load its models. Repeated
            // capture shortcuts must not silently discard the pending result.
            break
        }
    }

    func start() {
        guard !self.isActive, let display = self.displayProvider() else { return }

        let mode = self.modeProvider()

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
        self.saveMode(mode)
        self.toolbar.setMode(mode)
        self.selectionManager.setMode(mode)
    }

    func cancel() {
        guard self.isActive else { return }

        let wasProcessing = self.state == .processing
        self.sessionID = UUID()
        self.processingTask?.cancel()
        self.processingTask = nil
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.escapeMonitor.stop()
        self.hideSelectionUI()
        self.state = .idle
        if wasProcessing {
            self.onEvent?(.processingChanged(false))
        }
        self.onEvent?(.activityChanged(false))
    }

    private func hideSelectionUI() {
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
        self.onEvent?(.processingChanged(true))

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

        let timeout = self.processingTimeout
        self.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, sessionID == id, state == .processing else { return }

            self.cancel()
            self.onEvent?(.failed(CaptureError.timedOut))
        }
    }

    isolated deinit {
        escapeMonitor.stop()
        processingTask?.cancel()
        timeoutTask?.cancel()
    }
}

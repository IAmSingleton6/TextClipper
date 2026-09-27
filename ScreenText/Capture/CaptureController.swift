import CoreGraphics
import Foundation
import KeyboardShortcuts

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
    var isActive: Bool {
        self.state != .idle
    }

    var onEvent: ((CaptureEvent) -> Void)?
    var selectedMode: CaptureMode {
        self.toolbarModel.mode
    }

    private let clipboardService: any ClipboardWriting
    private let ocrService: any TextRecognizing
    private let captureService: any ScreenCapturing
    private var processingTask: Task<Void, Never>?
    private var sessionID = UUID()
    private let toolbar: any CaptureToolbarPresenting
    private let selectionManager: any SelectionManaging
    private let savedModeProvider: (() -> CaptureMode)?
    private let saveMode: (CaptureMode) -> Void
    private var lastSelectedMode: CaptureMode?
    private let displayProvider: () -> SelectionDisplay?
    private let toolbarModel = CaptureToolbarModel()
    private var escapeTask: Task<Void, Never>?

    init(clipboardService: any ClipboardWriting = ClipboardService(),
         ocrService: any TextRecognizing = OCRService(),
         captureService: any ScreenCapturing = ScreenCaptureService(),
         toolbar: any CaptureToolbarPresenting = CaptureToolbarWindow(),
         selectionManager: any SelectionManaging = SelectionManager(),
         displayProvider: @escaping () -> SelectionDisplay? = SelectionDisplay.atMouse,
         savedModeProvider: (() -> CaptureMode)? = nil,
         saveMode: @escaping (CaptureMode) -> Void = { _ in })
    {
        self.clipboardService = clipboardService
        self.ocrService = ocrService
        self.captureService = captureService
        self.toolbar = toolbar
        self.selectionManager = selectionManager
        self.displayProvider = displayProvider
        self.savedModeProvider = savedModeProvider
        self.saveMode = saveMode
    }

    func toggle() {
        if self.isActive {
            self.cancel()
        } else {
            self.start()
        }
    }

    func start() {
        guard !self.isActive, let display = displayProvider() else { return }
        self.toolbarModel.mode = self.savedModeProvider?() ?? self.lastSelectedMode ?? .box
        guard self.selectionManager.prepare(
            display: display, mode: self.toolbarModel.mode,
            onEvent: { [weak self] event in
                switch event {
                case .started: self?.selectionStarted()
                case let .completed(selection): self?.selectionCompleted(selection)
                case .cancelled: self?.cancel()
                }
            },
        ) else { return }
        guard self.toolbar.show(
            display: display, model: self.toolbarModel,
            onAction: { [weak self] action in
                switch action {
                case let .selectMode(mode): self?.selectMode(mode)
                case .cancel: self?.cancel()
                }
            },
        ) else {
            self.selectionManager.hide()
            return
        }
        self.selectionManager.setCursorExclusionRect(self.toolbar.cursorExclusionRect)
        self.state = .toolbar
        self.onEvent?(.started(display))
        self.onEvent?(.activityChanged(true))
        self.listenForEscape()
    }

    func selectMode(_ mode: CaptureMode) {
        guard self.state == .toolbar else { return }
        self.toolbarModel.mode = mode
        self.lastSelectedMode = mode
        self.saveMode(mode)
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
        self.escapeTask?.cancel()
        self.escapeTask = nil
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
        guard case let .selecting(mode) = state, mode.accepts(selection.shape) else { return }
        self.hideSelectionUI()
        self.state = .processing
        let id = UUID()
        self.sessionID = id
        let service = self.captureService
        let recognizer = self.ocrService
        self.processingTask = Task { [weak self] in
            do {
                let image = try await service.capture(region: selection)
                guard !Task.isCancelled, self?.sessionID == id else { return }
                let text = try await recognizer.recognizeText(from: image)
                guard !Task.isCancelled, let self, sessionID == id else { return }
                guard try self.clipboardService.copy(text) else {
                    self.cancel()
                    self.onEvent?(.noTextFound)
                    return
                }
                self.cancel()
                self.onEvent?(.textRecognized(text))
            } catch {
                guard !Task.isCancelled, let self, sessionID == id else { return }
                self.cancel()
                self.onEvent?(.failed(error))
            }
        }
    }

    private func listenForEscape() {
        // Register only during a capture session; no Accessibility permission or
        // persistent Escape shortcut setting is needed.
        let events = KeyboardShortcuts.events(for: .init(.escape, modifiers: []))
        let onCancel = { [weak self] in self?.cancel() }
        self.escapeTask = Task {
            for await event in events where event == .keyDown {
                guard !Task.isCancelled else { return }
                onCancel()
            }
        }
    }

    deinit {
        escapeTask?.cancel()
        processingTask?.cancel()
    }
}

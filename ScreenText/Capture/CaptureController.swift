import Foundation
import CoreGraphics
import KeyboardShortcuts

enum CaptureState: Equatable {
    case idle
    case toolbar
    case selecting(CaptureMode)
    case processing
}

@MainActor
final class CaptureController {
    private(set) var state: CaptureState = .idle
    var isActive: Bool { state != .idle }
    var onCaptureStarted: ((SelectionDisplay) -> Void)?
    var onNoTextFound: (() -> Void)?
    var onTextRecognized: ((String) -> Void)?
    var onCaptureFailed: ((Error) -> Void)?
    var selectedMode: CaptureMode { toolbarModel.mode }
    var onActivityChanged: ((Bool) -> Void)?

    private let clipboardService: any ClipboardWriting
    private let ocrService: any TextRecognizing
    private let captureService: any ScreenCapturing
    private var processingTask: Task<Void, Never>?
    private var sessionID = UUID()
    private let toolbar: any CaptureToolbarPresenting
    private let selectionManager: any SelectionManaging
    private let defaultModeProvider: () -> CaptureMode
    private let displayProvider: () -> SelectionDisplay?
    private let toolbarModel = CaptureToolbarModel()
    private var escapeTask: Task<Void, Never>?

    init(clipboardService: any ClipboardWriting = ClipboardService(),
         ocrService: any TextRecognizing = OCRService(),
         captureService: any ScreenCapturing = ScreenCaptureService(),
         toolbar: any CaptureToolbarPresenting = CaptureToolbarWindow(),
         selectionManager: any SelectionManaging = SelectionManager(),
         displayProvider: @escaping () -> SelectionDisplay? = SelectionDisplay.atMouse,
         defaultModeProvider: @escaping () -> CaptureMode = { .box }) {
        self.clipboardService = clipboardService
        self.ocrService = ocrService
        self.captureService = captureService
        self.toolbar = toolbar
        self.selectionManager = selectionManager
        self.displayProvider = displayProvider
        self.defaultModeProvider = defaultModeProvider
    }

    func toggle() {
        if isActive {
            cancel()
        } else {
            start()
        }
    }

    func start() {
        guard !isActive, let display = displayProvider() else { return }
        toolbarModel.mode = defaultModeProvider()
        guard selectionManager.prepare(
            display: display, mode: toolbarModel.mode,
            onStarted: { [weak self] in self?.selectionStarted() },
            onCompleted: { [weak self] selection in self?.selectionCompleted(selection) },
            onCancelled: { [weak self] in self?.cancel() }
        ) else { return }
        guard toolbar.show(
            display: display, model: toolbarModel,
            onModeSelected: { [weak self] mode in self?.selectMode(mode) },
            onCancel: { [weak self] in self?.cancel() }
        ) else {
            selectionManager.hide()
            return
        }
        state = .toolbar
        onCaptureStarted?(display)
        onActivityChanged?(true)
        listenForEscape()
    }

    func selectMode(_ mode: CaptureMode) {
        guard state == .toolbar else { return }
        toolbarModel.mode = mode
        selectionManager.setMode(mode)
    }

    func cancel() {
        guard isActive else { return }
        sessionID = UUID()
        processingTask?.cancel()
        processingTask = nil
        hideSelectionUI()
        state = .idle
        onActivityChanged?(false)
    }

    private func hideSelectionUI() {
        escapeTask?.cancel()
        escapeTask = nil
        toolbar.hide()
        selectionManager.hide()
    }

    private func selectionStarted() {
        guard state == .toolbar else { return }
        state = .selecting(selectedMode)
        toolbar.hide()
    }

    private func selectionCompleted(_ selection: Selection) {
        guard case .selecting(let mode) = state, selection.shape == mode.selectionShape else { return }
        hideSelectionUI()
        state = .processing
        let id = UUID()
        sessionID = id
        let service = captureService
        let recognizer = ocrService
        processingTask = Task { [weak self] in
            do {
                let image = try await service.capture(region: selection)
                guard !Task.isCancelled, self?.sessionID == id else { return }
                let text = try await recognizer.recognizeText(from: image)
                guard !Task.isCancelled, let self, self.sessionID == id else { return }
                guard try self.clipboardService.copy(text) else {
                    self.cancel()
                    self.onNoTextFound?()
                    return
                }
                self.cancel()
                self.onTextRecognized?(text)
            } catch {
                guard !Task.isCancelled, let self, self.sessionID == id else { return }
                self.cancel()
                self.onCaptureFailed?(error)
            }
        }
    }

    private func listenForEscape() {
        // Register only during a capture session; no Accessibility permission or
        // persistent Escape shortcut setting is needed.
        let events = KeyboardShortcuts.events(for: .init(.escape, modifiers: []))
        let onCancel = { [weak self] in self?.cancel() }
        escapeTask = Task {
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

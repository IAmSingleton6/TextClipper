import AppKit
@testable import ScreenText
import Testing

@MainActor
final class SelectionFixture {
    let manager = SelectionManager()
    let display: SelectionDisplay
    private let initialMode: CaptureMode
    private let dispatchThroughWindow: Bool
    private let onEvent: ((SelectionFixture, SelectionEvent<Selection>) -> Void)?
    private(set) var completed: [Selection] = []
    private(set) var starts = 0
    private(set) var cancellations = 0

    init(
        display: SelectionDisplay = testDisplay,
        initialMode: CaptureMode = .box,
        dispatchThroughWindow: Bool = false,
        onEvent: ((SelectionFixture, SelectionEvent<Selection>) -> Void)? = nil,
    ) {
        self.display = display
        self.initialMode = initialMode
        self.dispatchThroughWindow = dispatchThroughWindow
        self.onEvent = onEvent
    }

    var isVisible: Bool {
        self.manager.window?.isVisible == true
    }

    var window: SelectionWindow {
        get throws { try #require(self.manager.window) }
    }

    var view: SelectionView {
        get throws { try self.window.selectionView }
    }

    func start() throws {
        let prepared = self.manager.prepare(
            display: self.display,
            mode: self.initialMode,
            onEvent: { [weak self] event in
                guard let self else { return }
                switch event {
                case .started: self.starts += 1
                case let .completed(selection): self.completed.append(selection)
                case .cancelled: self.cancellations += 1
                }
                self.onEvent?(self, event)
            },
        )
        try #require(prepared)
    }

    func waitUntilFocused() async throws {
        try await NativeWindow.waitUntilFocused(self.window)
    }

    func selectMode(_ mode: CaptureMode) {
        self.manager.setMode(mode)
    }

    func hide() {
        self.manager.hide()
    }

    func cancel() throws {
        try self.view.cancelOperation(nil)
    }

    func press(at point: CGPoint) throws {
        try self.send(.leftMouseDown, at: point)
    }

    func drag(to point: CGPoint) throws {
        try self.send(.leftMouseDragged, at: point)
    }

    func release(at point: CGPoint) throws {
        try self.send(.leftMouseUp, at: point)
    }

    private func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
        let window = try self.window
        let event = try NativeMouse.event(type, at: point, window: window)
        if self.dispatchThroughWindow {
            window.sendEvent(event)
        } else {
            switch type {
            case .leftMouseDown: window.selectionView.mouseDown(with: event)
            case .leftMouseDragged: window.selectionView.mouseDragged(with: event)
            case .leftMouseUp: window.selectionView.mouseUp(with: event)
            default: Issue.record("Unsupported selection mouse event")
            }
        }
    }

    isolated deinit { manager.hide() }
}

@MainActor
final class SelectionViewFixture {
    let view: SelectionView
    private(set) var cancellations = 0
    private(set) var completed: [SelectionGeometry] = []

    init(mode: CaptureMode = .freehand, size: CGSize = .init(width: 100, height: 100)) {
        self.view = SelectionView(frame: CGRect(origin: .zero, size: size))
        self.view.mode = mode
        self.view.onEvent = { [weak self] event in
            switch event {
            case .cancelled: self?.cancellations += 1
            case let .completed(geometry): self?.completed.append(geometry)
            case .started: break
            }
        }
    }

    func press(at point: CGPoint) throws {
        try self.view.mouseDown(with: NativeMouse.event(.leftMouseDown, at: point))
    }

    func drag(to point: CGPoint) throws {
        try self.view.mouseDragged(with: NativeMouse.event(.leftMouseDragged, at: point))
    }

    func release(at point: CGPoint) throws {
        try self.view.mouseUp(with: NativeMouse.event(.leftMouseUp, at: point))
    }

    func renderedOverlay(scale: CGFloat? = nil) throws -> NSBitmapImageRep {
        let bitmap: NSBitmapImageRep
        if let scale {
            bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(self.view.bounds.width * scale),
                pixelsHigh: Int(self.view.bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
            ))
            bitmap.size = self.view.bounds.size
        } else {
            bitmap = try #require(self.view.bitmapImageRepForCachingDisplay(in: self.view.bounds))
        }
        self.view.cacheDisplay(in: self.view.bounds, to: bitmap)
        return bitmap
    }
}

import AppKit

@MainActor
protocol SelectionManaging: AnyObject {
    func prepare(display: SelectionDisplay, mode: CaptureMode, onEvent: @escaping (SelectionEvent<Selection>) -> Void) -> Bool
    func setMode(_ mode: CaptureMode)
    func setCursorExclusionRect(_ rect: CGRect?)
    func hide()
}

extension SelectionManaging {
    func setCursorExclusionRect(_: CGRect?) {}
}

@MainActor
final class SelectionManager: SelectionManaging {
    private(set) var window: SelectionWindow?
    private var previousApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var cursorTimer: Timer?
    private var cursorExclusionRect: CGRect?

    func prepare(display: SelectionDisplay, mode: CaptureMode, onEvent: @escaping (SelectionEvent<Selection>) -> Void) -> Bool {
        self.hide()
        guard [display.frame.minX, display.frame.minY, display.frame.maxX, display.frame.maxY].allSatisfy(\.isFinite),
              display.frame.width > 0, display.frame.height > 0 else { return false }
        let window = SelectionWindow(displayFrame: display.frame)
        self.window = window
        window.selectionView.mode = mode
        window.selectionView.onEvent = { [weak self] event in
            switch event {
            case .started:
                onEvent(.started)
            case let .completed(geometry):
                // Tear down the UI synchronously before handing the result downstream.
                self?.hide()
                onEvent(.completed(Selection(displayID: display.id, rect: geometry.rect, shape: geometry.shape)))
            case .cancelled:
                self?.hide()
                onEvent(.cancelled)
            }
        }
        // Cursor changes from an inactive application do not reliably reach
        // the desktop until a mouse event. Make this window both main and key
        // before activation, so capture owns focus rather than another window.
        let foreground = NSWorkspace.shared.frontmostApplication
        if foreground?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            self.previousApplication = foreground
        }
        self.activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main,
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                guard let window, window.isVisible else { return }
                window.makeMain()
                window.makeKey()
                window.makeFirstResponder(window.selectionView)
                window.resetCursorRects()
                NSCursor.crosshair.set()
            }
        }
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
        window.makeFirstResponder(window.selectionView)
        window.displayIfNeeded()
        window.resetCursorRects()
        window.selectionView.updateTrackingAreas()
        NSApp.activate(ignoringOtherApps: true)
        self.maintainCaptureCursor()
        return true
    }

    func setMode(_ mode: CaptureMode) {
        self.window?.selectionView.mode = mode
    }

    func setCursorExclusionRect(_ rect: CGRect?) {
        self.cursorExclusionRect = rect
        self.updateCursor()
    }

    private func updateCursor() {
        guard self.window?.isVisible == true else { return }
        let cursor: NSCursor = self.cursorExclusionRect?.contains(NSEvent.mouseLocation) == true ? .arrow : .crosshair
        cursor.set()
    }

    private func maintainCaptureCursor() {
        self.updateCursor()
        // AppKit and the previously active app can reset the cursor while
        // activation finishes, without sending this view a mouse event.
        // Maintain the session cursor until teardown, including a stationary
        // pointer. The toolbar retains its arrow via the exclusion rectangle.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated { self.updateCursor() }
        }
        self.cursorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func hide() {
        self.cursorTimer?.invalidate()
        self.cursorTimer = nil
        self.cursorExclusionRect = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        guard let window else { return }
        // Relinquish activation before removing the main window; otherwise
        // AppKit may promote and raise another app window during teardown.
        let previous = self.previousApplication
        self.previousApplication = nil
        if let previous, NSApp.isActive {
            NSApp.yieldActivation(to: previous)
            NSApp.deactivate()
            previous.activate(from: NSRunningApplication.current, options: [])
        }
        window.selectionView.reset()
        window.selectionView.onEvent = nil
        window.orderOut(nil)
        NSCursor.arrow.set()
        window.contentView = nil
        self.window = nil
    }
}

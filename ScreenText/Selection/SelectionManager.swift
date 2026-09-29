import AppKit

@MainActor
protocol SelectionManaging: AnyObject {
    func prepare(
        display: SelectionDisplay,
        mode: CaptureMode,
        onEvent: @escaping (SelectionEvent<Selection>) -> Void,
    ) -> Bool
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

    func prepare(
        display: SelectionDisplay,
        mode: CaptureMode,
        onEvent: @escaping (SelectionEvent<Selection>) -> Void,
    ) -> Bool {
        guard self.isValid(display.frame) else {
            return false
        }

        self.hide()

        let window = self.makeSelectionWindow(
            display: display,
            mode: mode,
            onEvent: onEvent,
        )
        self.window = window
        self.rememberPreviousApplication()

        self.observeActivation(for: window)
        self.show(window)

        return true
    }

    private func isValid(_ frame: CGRect) -> Bool {
        [
            frame.minX,
            frame.minY,
            frame.maxX,
            frame.maxY,
        ].allSatisfy(\.isFinite)
            && frame.width > 0
            && frame.height > 0
    }

    private func makeSelectionWindow(
        display: SelectionDisplay,
        mode: CaptureMode,
        onEvent: @escaping (SelectionEvent<Selection>) -> Void,
    ) -> SelectionWindow {
        let window = SelectionWindow(displayFrame: display.frame)
        window.mode = mode

        window.onSelectionEvent = { [weak self] event in
            switch event {
            case .started:
                onEvent(.started)
            case let .completed(geometry):
                // Tear down the UI synchronously before handing the result downstream.
                self?.hide()
                onEvent(.completed(
                    Selection(
                        displayID: display.id,
                        rect: geometry.rect,
                        shape: geometry.shape,
                    ),
                ))
            case .cancelled:
                self?.hide()
                onEvent(.cancelled)
            }
        }

        return window
    }

    private func rememberPreviousApplication() {
        let foreground = NSWorkspace.shared.frontmostApplication
        if foreground?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            self.previousApplication = foreground
        }
    }

    private func observeActivation(for window: SelectionWindow) {
        self.activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main,
        ) { [weak window] _ in
            Task { @MainActor [weak window] in
                window?.reclaimSelectionFocus()
            }
        }
    }

    private func show(_ window: SelectionWindow) {
        window.presentForSelection()

        NSApp.activate(ignoringOtherApps: true)
        window.startCursorMaintenance()
    }

    func setMode(_ mode: CaptureMode) {
        self.window?.mode = mode
    }

    func setCursorExclusionRect(_ rect: CGRect?) {
        self.window?.setCursorExclusionRect(rect)
    }

    func hide() {
        self.stopObservingActivation()
        guard let window else { return }
        self.restorePreviousApplication()
        window.dismissSelection()
        self.window = nil
    }

    private func stopObservingActivation() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func restorePreviousApplication() {
        // Relinquish activation before removing the main window; otherwise
        // AppKit may promote and raise another app window during teardown.
        let previous = self.previousApplication
        self.previousApplication = nil
        if let previous, NSApp.isActive {
            NSApp.yieldActivation(to: previous)
            NSApp.deactivate()
            previous.activate(from: NSRunningApplication.current, options: [])
        }
    }
}

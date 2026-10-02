import AppKit

@MainActor
protocol SelectionManaging: AnyObject {
    func prepare(
        display: SelectionDisplay,
        mode: CaptureMode,
        onEvent: @escaping (SelectionEvent<Selection>) -> Void,
    ) -> Bool
    func setMode(_ mode: CaptureMode)
    func setCursorExclusionRect(_ rect: ScreenRect?)
    func hide()
}

extension SelectionManaging {
    func setCursorExclusionRect(_: ScreenRect?) {}
}

@MainActor
final class SelectionManager: SelectionManaging {
    private(set) var window: SelectionWindow?
    private let activation = SelectionActivationSession()

    func prepare(
        display: SelectionDisplay,
        mode: CaptureMode,
        onEvent: @escaping (SelectionEvent<Selection>) -> Void,
    ) -> Bool {
        guard display.hasValidFrame else {
            return false
        }

        self.hide()
        let window = self.makeSelectionWindow(display: display, mode: mode, onEvent: onEvent)
        self.window = window
        self.activation.begin(for: window)
        window.presentForSelection()
        window.startCursorMaintenance()

        return true
    }

    private func makeSelectionWindow(
        display: SelectionDisplay,
        mode: CaptureMode,
        onEvent: @escaping (SelectionEvent<Selection>) -> Void,
    ) -> SelectionWindow {
        let window = SelectionWindow(displayFrame: display.frame)
        window.mode = mode

        window.onSelectionEvent = { [weak self] event in
            self?.handleWindowEvent(event, displayID: display.id, onEvent: onEvent)
        }

        return window
    }

    private func handleWindowEvent(
        _ event: SelectionEvent<SelectionGeometry>,
        displayID: CGDirectDisplayID,
        onEvent: (SelectionEvent<Selection>) -> Void,
    ) {
        switch event {
        case .started:
            onEvent(.started)
        case let .completed(geometry):
            self.hide()
            onEvent(.completed(
                Selection(
                    displayID: displayID,
                    rect: geometry.rect,
                    shape: geometry.shape,
                ),
            ))
        case .cancelled:
            self.hide()
            onEvent(.cancelled)
        }
    }

    func setMode(_ mode: CaptureMode) {
        self.window?.mode = mode
    }

    func setCursorExclusionRect(_ rect: ScreenRect?) {
        self.window?.setCursorExclusionRect(rect)
    }

    func hide() {
        self.activation.end()
        guard let window else { return }
        window.dismissSelection()
        self.window = nil
    }
}

import AppKit

@MainActor
protocol SelectionManaging: AnyObject {
    func prepare(display: SelectionDisplay, mode: CaptureMode, onStarted: @escaping () -> Void,
                 onCompleted: @escaping (Selection) -> Void, onCancelled: @escaping () -> Void) -> Bool
    func setMode(_ mode: CaptureMode)
    func hide()
}

@MainActor
final class SelectionManager: SelectionManaging {
    private(set) var window: SelectionWindow?

    func prepare(display: SelectionDisplay, mode: CaptureMode, onStarted: @escaping () -> Void,
                 onCompleted: @escaping (Selection) -> Void, onCancelled: @escaping () -> Void) -> Bool {
        hide()
        guard display.frame.width > 0 && display.frame.height > 0 else { return false }
        let window = SelectionWindow(displayFrame: display.frame)
        self.window = window
        window.selectionView.mode = mode
        window.selectionView.onStarted = onStarted
        window.selectionView.onCancelled = { [weak self] in
            self?.hide()
            onCancelled()
        }
        window.selectionView.onFinished = { [weak self] rect in
            // Tear down the UI synchronously, before handing the result downstream.
            self?.hide()
            guard let rect else {
                onCancelled()
                return
            }
            onCompleted(Selection(displayID: display.id, rect: rect, shape: .rectangle))
        }
        // The clear overlay is ready for the very first drag. The toolbar is
        // subsequently ordered above it, so its controls remain clickable.
        window.orderFrontRegardless()
        return true
    }

    func setMode(_ mode: CaptureMode) {
        window?.selectionView.mode = mode
    }

    func hide() {
        guard let window else { return }
        window.selectionView.reset()
        window.selectionView.onStarted = nil
        window.selectionView.onFinished = nil
        window.selectionView.onCancelled = nil
        window.orderOut(nil)
        window.contentView = nil
        self.window = nil
    }
}

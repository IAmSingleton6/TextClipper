import AppKit

/// Manages application focus for one selection session.
@MainActor
final class SelectionActivationSession {
    private var previousApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    func begin(for window: SelectionWindow) {
        self.rememberPreviousApplication()
        self.observeActivation(for: window)
        self.activate()
    }

    func end() {
        self.stopObservingActivation()
        self.restorePreviousApplication()
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

    private func activate() {
        if let previousApplication {
            // Request activation from the app that was active when selection began.
            _ = NSRunningApplication.current.activate(
                from: previousApplication,
                options: [],
            )
        } else {
            NSApp.activate()
        }
    }

    private func stopObservingActivation() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func restorePreviousApplication() {
        // Restore the previous app before the selection window is removed,
        // otherwise AppKit may promote another app window during teardown
        let previous = self.previousApplication
        self.previousApplication = nil

        guard let previous, NSApp.isActive else {
            return
        }

        NSApp.yieldActivation(to: previous)
        NSApp.deactivate()
        previous.activate(
            from: NSRunningApplication.current,
            options: [],
        )
    }
}

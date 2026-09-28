import AppKit

@MainActor
final class DisplayConfigurationObserver: NSObject {
    private let notificationCenter: NotificationCenter
    private let onChange: () -> Void

    init(center: NotificationCenter = .default, onChange: @escaping () -> Void) {
        self.notificationCenter = center
        self.onChange = onChange
        super.init()

        center.addObserver(
            self,
            selector: #selector(self.changed),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
    }

    /// AppKit delivers its display-configuration notification on the main thread.
    /// Keep delivery synchronous so captures are invalidated before posting returns.
    /// An async notification sequence would defer cancellation to a later actor turn.
    @objc private func changed() {
        self.onChange()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}

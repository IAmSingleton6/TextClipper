import AppKit

@MainActor
final class DisplayConfigurationObserver: NSObject {
    private let center: NotificationCenter
    private let onChange: () -> Void

    init(center: NotificationCenter = .default, onChange: @escaping () -> Void) {
        self.center = center
        self.onChange = onChange
        super.init()
        center.addObserver(self, selector: #selector(changed),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // AppKit delivers its display-configuration notification on the main thread.
    @objc private func changed() { onChange() }

    deinit { center.removeObserver(self) }
}

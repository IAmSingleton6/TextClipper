import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
    private let defaults: UserDefaults
    var showCapturedText: Bool {
        didSet { defaults.set(showCapturedText, forKey: "showCapturedText") }
    }
    var defaultMode: CaptureMode {
        didSet { defaults.set(defaultMode == .circle ? "circle" : "box", forKey: "defaultSelectionMode") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCapturedText = defaults.bool(forKey: "showCapturedText")
        defaultMode = defaults.string(forKey: "defaultSelectionMode") == "circle" ? .circle : .box
    }
}

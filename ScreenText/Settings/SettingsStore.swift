import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
    private let defaults: UserDefaults
    var showCapturedText: Bool {
        didSet { self.defaults.set(self.showCapturedText, forKey: "showCapturedText") }
    }

    /// Keep the existing storage key so upgrades retain the last used mode.
    var lastSelectionMode: CaptureMode {
        didSet { self.defaults.set(self.lastSelectionMode == .freehand ? "freehand" : "box", forKey: "defaultSelectionMode") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showCapturedText = defaults.object(forKey: "showCapturedText") == nil
            ? true : defaults.bool(forKey: "showCapturedText")
        let savedMode = defaults.string(forKey: "defaultSelectionMode")
        self.lastSelectionMode = ["freehand", "circle"].contains(savedMode ?? "") ? .freehand : .box
    }

    /// Show setup once per user, including when upgrading from a version without setup.
    func consumeFirstLaunch() -> Bool {
        guard !self.defaults.bool(forKey: "hasShownInitialSettings") else { return false }
        self.defaults.set(true, forKey: "hasShownInitialSettings")
        return true
    }
}

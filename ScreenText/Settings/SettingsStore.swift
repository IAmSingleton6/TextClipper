import Foundation

@MainActor
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // The Phase 9 preview preference. The rest of Settings follows in Phase 10.
    var showCapturedText: Bool {
        get { defaults.bool(forKey: "showCapturedText") }
        set { defaults.set(newValue, forKey: "showCapturedText") }
    }
}

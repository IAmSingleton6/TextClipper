import Observation

@MainActor
@Observable
final class SettingsStore {
    private let persistence: SettingsPersistence
    private(set) var lastSelectionMode: CaptureMode

    var showCapturedText: Bool {
        didSet { self.persistence.showCapturedText = self.showCapturedText }
    }

    init(persistence: SettingsPersistence) {
        self.persistence = persistence
        self.showCapturedText = persistence.showCapturedText
        self.lastSelectionMode = persistence.lastSelectionMode
    }

    func selectCaptureMode(_ mode: CaptureMode) {
        self.lastSelectionMode = mode
        self.persistence.lastSelectionMode = mode
    }

    /// Show setup once per user, including when upgrading from a version without setup.
    func consumeFirstLaunch() -> Bool {
        guard !self.persistence.hasShownInitialSettings else { return false }
        self.persistence.hasShownInitialSettings = true
        return true
    }
}

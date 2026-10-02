import Foundation

struct SettingsPersistence {
    private enum StorageKey: String {
        case showCapturedText
        case lastSelectionMode
        case hasShownInitialSettings
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var showCapturedText: Bool {
        get {
            self.defaults.object(forKey: StorageKey.showCapturedText.rawValue) as? Bool
                ?? SettingsDefaults.showCapturedText
        }
        nonmutating set { self.defaults.set(newValue, forKey: StorageKey.showCapturedText.rawValue) }
    }

    var lastSelectionMode: CaptureMode {
        get {
            guard let savedMode = self.defaults.string(forKey: StorageKey.lastSelectionMode.rawValue)
            else { return SettingsDefaults.captureMode }
            return CaptureMode(rawValue: savedMode) ?? SettingsDefaults.captureMode
        }
        nonmutating set { self.defaults.set(newValue.rawValue, forKey: StorageKey.lastSelectionMode.rawValue) }
    }

    var hasShownInitialSettings: Bool {
        get { self.defaults.bool(forKey: StorageKey.hasShownInitialSettings.rawValue) }
        nonmutating set { self.defaults.set(newValue, forKey: StorageKey.hasShownInitialSettings.rawValue) }
    }
}

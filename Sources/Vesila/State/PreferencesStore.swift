import Foundation

/// Persists `VesilaPreferences` and the onboarding flag in UserDefaults.
/// The key names predate this type and must stay stable so existing installs keep their settings.
/// The key of a removed display setting is deliberately never read, so Stay Active When Locked
/// always starts off rather than inheriting an unrelated setting. There is no migration.
struct PreferencesStore {
    private enum Key {
        static let duration = "selectedDuration"
        static let stayActiveWhenLocked = "stayActiveWhenLocked"
        static let hasLastActiveFeatures = "lastEnabledConfiguration.hasValue"
        static let lastActivePresence = "lastEnabledConfiguration.presence"
        static let lastActiveSystemAwake = "lastEnabledConfiguration.systemAwake"
        static let onboardingCompleted = "onboardingCompleted"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> VesilaPreferences {
        var preferences = VesilaPreferences()
        if let rawDuration = defaults.string(forKey: Key.duration),
           let duration = VesilaDuration(rawValue: rawDuration) {
            preferences.duration = duration
        }
        if defaults.object(forKey: Key.stayActiveWhenLocked) != nil {
            preferences.stayActiveWhenLocked = defaults.bool(forKey: Key.stayActiveWhenLocked)
        }
        if defaults.bool(forKey: Key.hasLastActiveFeatures) {
            let features = MainFeatures(
                presence: defaults.bool(forKey: Key.lastActivePresence),
                systemAwake: defaults.bool(forKey: Key.lastActiveSystemAwake)
            )
            if !features.isEmpty {
                preferences.lastActiveFeatures = features
            }
        }
        return preferences
    }

    func save(_ preferences: VesilaPreferences) {
        defaults.set(preferences.duration.rawValue, forKey: Key.duration)
        defaults.set(preferences.stayActiveWhenLocked, forKey: Key.stayActiveWhenLocked)
        defaults.set(true, forKey: Key.hasLastActiveFeatures)
        defaults.set(preferences.lastActiveFeatures.presence, forKey: Key.lastActivePresence)
        defaults.set(preferences.lastActiveFeatures.systemAwake, forKey: Key.lastActiveSystemAwake)
    }

    var isOnboardingCompleted: Bool {
        defaults.bool(forKey: Key.onboardingCompleted)
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: Key.onboardingCompleted)
    }
}

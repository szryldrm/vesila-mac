import Foundation

/// Persists `VesilaPreferences` and the onboarding flag in UserDefaults.
/// The key names predate this type and must stay stable so existing installs keep their settings.
struct PreferencesStore {
    private enum Key {
        static let duration = "selectedDuration"
        static let keepDisplayAwake = "keepDisplayAwake"
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
        if defaults.object(forKey: Key.keepDisplayAwake) != nil {
            preferences.keepDisplayAwake = defaults.bool(forKey: Key.keepDisplayAwake)
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
        defaults.set(preferences.keepDisplayAwake, forKey: Key.keepDisplayAwake)
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

import Foundation

/// Persists `VesilaPreferences` and the onboarding flag in UserDefaults.
/// The key names predate this type and must stay stable so existing installs keep their settings.
/// The key of a removed display setting is deliberately never read, so Stay Active When Locked
/// always starts off rather than inheriting an unrelated setting. Legacy Presence-only activity
/// is restored as both features.
struct PreferencesStore {
    private enum Key {
        static let activationMode = "activationMode"
        static let scheduleDays = "schedule.days"
        static let scheduleStart = "schedule.startMinute"
        static let scheduleEnd = "schedule.endMinute"
        static let pausedWindowDay = "schedule.pausedWindowDay"
        static let duration = "selectedDuration"
        static let stayActiveWhenLocked = "stayActiveWhenLocked"
        static let hasLastActiveFeatures = "lastEnabledConfiguration.hasValue"
        static let lastActivePresence = "lastEnabledConfiguration.presence"
        static let lastActiveSystemAwake = "lastEnabledConfiguration.systemAwake"
        static let onboardingCompleted = "onboardingCompleted"
        static let lastLaunchedVersion = "lastLaunchedVersion"
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
                preferences.lastActiveFeatures = features.presence && !features.systemAwake ? .both : features
            }
        }
        if let rawMode = defaults.string(forKey: Key.activationMode), let mode = VesilaActivationMode(rawValue: rawMode) {
            preferences.activationMode = mode
        }
        if let days = defaults.object(forKey: Key.scheduleDays) as? [Int],
           let start = defaults.object(forKey: Key.scheduleStart) as? Int,
           let end = defaults.object(forKey: Key.scheduleEnd) as? Int {
            let schedule = VesilaSchedule(days: Set(days), startMinute: start, endMinute: end)
            if schedule.isValid { preferences.schedule = schedule }
        }
        preferences.pausedWindowDay = defaults.object(forKey: Key.pausedWindowDay) as? Date
        return preferences
    }

    func save(_ preferences: VesilaPreferences) {
        defaults.set(preferences.activationMode.rawValue, forKey: Key.activationMode)
        defaults.set(preferences.schedule.days.sorted(), forKey: Key.scheduleDays)
        defaults.set(preferences.schedule.startMinute, forKey: Key.scheduleStart)
        defaults.set(preferences.schedule.endMinute, forKey: Key.scheduleEnd)
        if let day = preferences.pausedWindowDay {
            defaults.set(day, forKey: Key.pausedWindowDay)
        } else {
            defaults.removeObject(forKey: Key.pausedWindowDay)
        }
        defaults.set(preferences.duration.rawValue, forKey: Key.duration)
        defaults.set(preferences.stayActiveWhenLocked, forKey: Key.stayActiveWhenLocked)
        defaults.set(true, forKey: Key.hasLastActiveFeatures)
        defaults.set(preferences.lastActiveFeatures.presence, forKey: Key.lastActivePresence)
        defaults.set(preferences.lastActiveFeatures.systemAwake || preferences.lastActiveFeatures.presence, forKey: Key.lastActiveSystemAwake)
    }

    var lastLaunchedVersion: String? {
        get { defaults.string(forKey: Key.lastLaunchedVersion) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastLaunchedVersion) }
    }

    var isOnboardingCompleted: Bool {
        defaults.bool(forKey: Key.onboardingCompleted)
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: Key.onboardingCompleted)
    }
}

import Foundation

/// Presence and System Awake: the two features that make up a Vesila session.
/// Keep Display Awake is deliberately not part of this. It is a preference subordinate to System Awake.
struct MainFeatures: Equatable {
    var presence = false
    var systemAwake = false

    static let none = MainFeatures()
    static let both = MainFeatures(presence: true, systemAwake: true)

    var isEmpty: Bool { !presence && !systemAwake }
}

enum VesilaDuration: String, CaseIterable {
    // Raw values are persisted in UserDefaults; don't rename the cases.
    case thirtyMinutes
    case oneHour
    case twoHours
    case threeHours
    case fiveHours
    case untilTurnedOff

    var seconds: TimeInterval? {
        switch self {
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .threeHours: return 3 * 60 * 60
        case .fiveHours: return 5 * 60 * 60
        case .untilTurnedOff: return nil
        }
    }

    /// Full name, used for tooltips and VoiceOver.
    var title: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .threeHours: return "3 hours"
        case .fiveHours: return "5 hours"
        case .untilTurnedOff: return "Until turned off"
        }
    }

    /// Pill label in the menu.
    var shortTitle: String {
        switch self {
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .threeHours: return "3h"
        case .fiveHours: return "5h"
        case .untilTurnedOff: return "∞"
        }
    }

    func expirationDate(from start: Date) -> Date? {
        seconds.map { start.addingTimeInterval($0) }
    }
}

/// Everything Vesila remembers across launches. Active features are never persisted:
/// every launch starts with both main features off.
struct VesilaPreferences: Equatable {
    var keepDisplayAwake = true
    var duration: VesilaDuration = .oneHour
    /// The combination right-click restores: the last non-empty one that was on. Both on first run.
    var lastActiveFeatures = MainFeatures.both
}

/// Vesila's complete application state, and the only place its rules are implemented.
/// `VesilaController` owns the single instance and mirrors it into the system services.
///
/// Invariants, maintained by the mutating methods below:
/// - A session exists exactly while at least one main feature is on. It starts on the
///   none → any transition; turning the other feature on or off doesn't restart it.
/// - `expirationDate` is nil whenever there is no session, or the duration is "Until turned off".
/// - Keep Display Awake only takes effect together with System Awake (`preventsDisplaySleep`),
///   and never affects the session.
struct VesilaState: Equatable {
    private(set) var activeFeatures = MainFeatures.none
    private(set) var expirationDate: Date?
    private(set) var preferences: VesilaPreferences

    init(preferences: VesilaPreferences = VesilaPreferences()) {
        self.preferences = preferences
    }

    var isSessionActive: Bool { !activeFeatures.isEmpty }

    var preventsDisplaySleep: Bool { activeFeatures.systemAwake && preferences.keepDisplayAwake }

    /// Time left in the session, or nil when there is no countdown.
    func remainingTime(at now: Date) -> TimeInterval? {
        guard let expirationDate else { return nil }
        return max(0, expirationDate.timeIntervalSince(now))
    }

    mutating func setPresence(_ isOn: Bool, now: Date) {
        var features = activeFeatures
        features.presence = isOn
        setActiveFeatures(features, now: now)
    }

    mutating func setSystemAwake(_ isOn: Bool, now: Date) {
        var features = activeFeatures
        features.systemAwake = isOn
        setActiveFeatures(features, now: now)
    }

    mutating func setActiveFeatures(_ features: MainFeatures, now: Date) {
        let sessionWasActive = isSessionActive
        activeFeatures = features
        guard isSessionActive else {
            expirationDate = nil
            return
        }
        preferences.lastActiveFeatures = features
        if !sessionWasActive {
            expirationDate = preferences.duration.expirationDate(from: now)
        }
    }

    /// Ends the session. Right-click, expiration, sleep/lock/lid-close, and quit all come through here.
    mutating func turnOff() {
        activeFeatures = .none
        expirationDate = nil
    }

    /// During a session the countdown restarts from `now`, or is removed for "Until turned off".
    mutating func selectDuration(_ duration: VesilaDuration, now: Date) {
        preferences.duration = duration
        if isSessionActive {
            expirationDate = duration.expirationDate(from: now)
        }
    }

    mutating func setKeepDisplayAwake(_ isOn: Bool) {
        preferences.keepDisplayAwake = isOn
    }
}

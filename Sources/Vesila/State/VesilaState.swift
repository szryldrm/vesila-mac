import Foundation

/// System Awake is the master activity feature; Presence depends on it.
/// Stay Active When Locked is deliberately not part of this. It is a preference, not a feature.
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
/// Manual launches start off; Scheduled launches evaluate the configured window.
struct VesilaPreferences: Equatable {
    /// When on and System Awake is active, a screen lock no longer ends the session. Off by default.
    var stayActiveWhenLocked = false
    var duration: VesilaDuration = .oneHour
    /// The combination right-click restores: the last non-empty one that was on. Both on first run.
    var lastActiveFeatures = MainFeatures.both
    var activationMode: VesilaActivationMode = .manual
    var schedule = VesilaSchedule()
    /// The start-of-day identity of a user-paused window. Stale days never match a new window.
    var pausedWindowDay: Date?
}

/// A system event that can end the session: sleep, screen lock, switching to another user, or
/// closing the laptop lid. Resume events separately trigger schedule evaluation.
enum VesilaInterruption: String {
    // Raw values are logged; don't rename the cases.
    case systemSleep
    case screenLocked
    case sessionResigned
    case lidClosed
}

/// Vesila's complete application state, and the only place its rules are implemented.
/// `VesilaController` owns the single instance and mirrors it into the system services.
///
/// Invariants, maintained by the mutating methods below:
/// - Presence implies System Awake. A session exists exactly while System Awake is on.
///   Changing Presence never starts, ends, or restarts a session.
/// - `expirationDate` is nil without a session. In Manual mode it follows the selected duration;
///   in Scheduled mode it is the current unpaused window's end, or nil for an outside session.
/// - Window membership and pause are derived from preferences, now, and Calendar. Only the
///   paused window's day is persisted; system ends never create a user override.
/// - Every interruption ends the session, except a screen lock while Stay Active When Locked
///   is on and System Awake is active. Resume events evaluate Scheduled mode; Manual stays off.
/// - Stay Active When Locked is available only while System Awake is active; its stored
///   preference is kept when System Awake turns off.
/// - Changing Stay Active When Locked never affects the session.
struct VesilaState: Equatable {
    private(set) var activeFeatures = MainFeatures.none
    private(set) var expirationDate: Date?
    private(set) var preferences: VesilaPreferences

    init(preferences: VesilaPreferences = VesilaPreferences()) {
        self.preferences = preferences
    }

    var isSessionActive: Bool { activeFeatures.systemAwake }

    /// Shared by the menu enablement and the screen-lock rule; independent of the stored choice.
    var isStayActiveWhenLockedAvailable: Bool { activeFeatures.systemAwake }

    /// Time left in the session, or nil when there is no countdown.
    func remainingTime(at now: Date) -> TimeInterval? {
        guard let expirationDate else { return nil }
        return max(0, expirationDate.timeIntervalSince(now))
    }

    mutating func setPresence(_ isOn: Bool, now: Date, calendar: Calendar = .current, userInitiated: Bool = true) {
        guard !isOn || activeFeatures.systemAwake else { return }
        var features = activeFeatures
        features.presence = isOn
        setActiveFeatures(features, now: now, calendar: calendar, userInitiated: userInitiated)
    }

    mutating func setSystemAwake(_ isOn: Bool, now: Date, calendar: Calendar = .current, userInitiated: Bool = true) {
        var features = activeFeatures
        features.systemAwake = isOn
        setActiveFeatures(features, now: now, calendar: calendar, userInitiated: userInitiated)
    }

    mutating func setActiveFeatures(_ features: MainFeatures, now: Date, calendar: Calendar = .current, userInitiated: Bool = true) {
        var features = features
        if !features.systemAwake { features.presence = false }
        let sessionWasActive = isSessionActive
        activeFeatures = features
        if userInitiated, preferences.activationMode == .scheduled,
           let window = preferences.schedule.window(containing: now, calendar: calendar) {
            if sessionWasActive && features.isEmpty {
                preferences.pausedWindowDay = calendar.startOfDay(for: window.start)
            } else if !sessionWasActive && !features.isEmpty {
                preferences.pausedWindowDay = nil
            }
        }
        guard isSessionActive else {
            expirationDate = nil
            return
        }
        preferences.lastActiveFeatures = features
        if preferences.activationMode == .scheduled {
            expirationDate = preferences.schedule.window(containing: now, calendar: calendar)?.end
        } else if !sessionWasActive {
            expirationDate = preferences.duration.expirationDate(from: now)
        }
    }

    /// System end: expiration, interruptions, service failure, and quit never pause a window.
    mutating func turnOff() {
        activeFeatures = .none
        expirationDate = nil
    }

    /// User end: only the current Scheduled window is paused.
    mutating func turnOffByUser(now: Date, calendar: Calendar = .current) {
        setActiveFeatures(.none, now: now, calendar: calendar)
    }

    func pausedWindow(at now: Date, calendar: Calendar) -> DateInterval? {
        guard preferences.activationMode == .scheduled,
              let window = preferences.schedule.window(containing: now, calendar: calendar),
              preferences.pausedWindowDay == calendar.startOfDay(for: window.start) else { return nil }
        return window
    }

    /// Idempotent schedule evaluation. Accessibility filters only a new restore; an existing
    /// session keeps its features. Lock/session availability gates activation, not adoption.
    mutating func evaluateSchedule(now: Date, calendar: Calendar, canActivate: Bool, canUsePresence: Bool = true) {
        guard preferences.activationMode == .scheduled else { return }
        guard let window = preferences.schedule.window(containing: now, calendar: calendar),
              pausedWindow(at: now, calendar: calendar) == nil else {
            if expirationDate != nil { turnOff() }
            return
        }
        if !isSessionActive && canActivate {
            var features = preferences.lastActiveFeatures
            if !canUsePresence { features.presence = false }
            setActiveFeatures(features, now: now, calendar: calendar, userInitiated: false)
        }
        if isSessionActive { expirationDate = window.end }
    }

    mutating func selectActivationMode(_ mode: VesilaActivationMode, now: Date, calendar: Calendar,
                                       canActivate: Bool, canUsePresence: Bool = true) {
        guard mode != preferences.activationMode else { return }
        preferences.activationMode = mode
        if mode == .scheduled {
            expirationDate = nil
            evaluateSchedule(now: now, calendar: calendar, canActivate: canActivate, canUsePresence: canUsePresence)
        } else if isSessionActive {
            expirationDate = preferences.duration.expirationDate(from: now)
        }
    }

    mutating func setSchedule(_ schedule: VesilaSchedule, now: Date, calendar: Calendar,
                              canActivate: Bool, canUsePresence: Bool = true) {
        guard schedule.isValid else { return }
        preferences.schedule = schedule
        evaluateSchedule(now: now, calendar: calendar, canActivate: canActivate, canUsePresence: canUsePresence)
    }

    /// During a session the countdown restarts from `now`, or is removed for "Until turned off".
    mutating func selectDuration(_ duration: VesilaDuration, now: Date) {
        preferences.duration = duration
        if isSessionActive && preferences.activationMode == .manual {
            expirationDate = duration.expirationDate(from: now)
        }
    }

    mutating func setStayActiveWhenLocked(_ isOn: Bool) {
        preferences.stayActiveWhenLocked = isOn
    }

    /// Whether `interruption` ends the session; if it does, end it with `turnOff()`.
    /// Only a screen lock can be ignored, and only while Stay Active When Locked is on
    /// and available because System Awake is active.
    /// Sleep, lid close, and switching to another user always end the session.
    func shouldEndSession(for interruption: VesilaInterruption) -> Bool {
        !(interruption == .screenLocked && preferences.stayActiveWhenLocked && isStayActiveWhenLockedAvailable)
    }
}

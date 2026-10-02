import Foundation
import OSLog

/// The single owner of Vesila's state and of every service that acts on it.
///
/// Every change, whether from the menu, right-click, the expiration timer, or a sleep/lock/lid
/// event, goes through `update(_:)`. It applies a `VesilaState` transition, brings the services in
/// line with the new state, persists preferences, and notifies the UI:
///
///     input ─▶ VesilaController ─▶ VesilaState ─▶ power assertions, Presence, expiration timer
///                                        └─▶ onChange ─▶ StatusBarController renders
///
/// Because services are always reconciled against the state (never toggled ad hoc), the
/// invariants hold by construction: System Awake off means no power assertions; no session
/// means no expiration timer; Manual launches start off, Scheduled launches evaluate the window, and
/// interruptions leave both main features off, except a screen lock while Stay Active When Locked is on and System Awake is active, which keeps
/// the running session untouched. Turning System Awake off keeps the stored lock preference.
/// Every interruption, that lock included, abandons a pending Presence activation. Resume and
/// clock events re-evaluate the schedule with lock/session availability, then replace one boundary
/// timer. Actual activity remains solely in VesilaState; no schedule membership is cached.
@MainActor
final class VesilaController {
    private(set) var state: VesilaState

    /// Called after every change so the UI can re-render from `state`.
    var onChange: ((VesilaState) -> Void)?

    /// Called when Presence was requested without Accessibility access. The UI explains why, and
    /// may call `activatePresenceWhenAccessibilityGranted()` once the user heads to System Settings.
    var onAccessibilityRequired: (() -> Void)?

    private static let accessibilityGrantTimeout: TimeInterval = 3 * 60

    private let preferencesStore: PreferencesStore
    private let isAccessibilityGranted: () -> Bool
    private let presenceKeeper: PresenceKeeper
    private let powerAssertions = PowerAssertionService()
    private let interruptionMonitor = InterruptionMonitor()
    /// Internal-readable so tests can fire the real timer instead of waiting out a duration.
    private(set) var expirationTimer: Timer?
    private var accessibilityGrantTimer: Timer?
    private(set) var scheduleTimer: Timer?
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let sessionSnapshot: () -> (locked: Bool, active: Bool)
    private var screenLocked: Bool
    private var sessionInactive: Bool
    private var sleeping = false
    private var lidClosed = false

    private var canScheduleActivate: Bool { !screenLocked && !sessionInactive && !sleeping && !lidClosed }

    /// `presenceKeeper` is only passed by tests, to drive its polls directly.
    init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        isAccessibilityGranted: @escaping () -> Bool = { AccessibilityPermission.isGranted },
        presenceKeeper: PresenceKeeper? = nil,
        now: @escaping () -> Date = { .now },
        calendar: @escaping () -> Calendar = { .current },
        sessionSnapshot: @escaping () -> (locked: Bool, active: Bool) = { InterruptionMonitor.sessionSnapshot() }
    ) {
        self.now = now
        self.calendar = calendar
        self.sessionSnapshot = sessionSnapshot
        let session = sessionSnapshot()
        screenLocked = session.locked
        sessionInactive = !session.active
        self.preferencesStore = preferencesStore
        self.isAccessibilityGranted = isAccessibilityGranted
        self.presenceKeeper = presenceKeeper ?? PresenceKeeper(isAccessibilityGranted: isAccessibilityGranted)
        state = VesilaState(preferences: preferencesStore.load())

        self.presenceKeeper.onAccessibilityRevoked = { [weak self] in
            self?.turnPresenceOffAfterAccessibilityRevoked()
        }
        interruptionMonitor.start(onInterruption: { [weak self] interruption in
            self?.handleInterruption(interruption)
        }, onResume: { [weak self] event in
            self?.handleResume(event)
        })
        evaluateSchedule()
    }

    // MARK: - Intents

    func setPresenceActive(_ isOn: Bool) {
        guard !isOn || isAccessibilityGranted() else {
            onAccessibilityRequired?()
            // The toggle already flipped itself on click; re-render so it shows the real state.
            onChange?(state)
            return
        }
        update { $0.setPresence(isOn, now: now(), calendar: calendar()) }
        if !state.isSessionActive { cancelPendingPresenceActivation() }
    }

    func setSystemAwakeActive(_ isOn: Bool) {
        update { $0.setSystemAwake(isOn, now: now(), calendar: calendar()) }
        if !state.isSessionActive { cancelPendingPresenceActivation() }
    }

    func setStayActiveWhenLocked(_ isOn: Bool) {
        update { $0.setStayActiveWhenLocked(isOn) }
    }

    func selectDuration(_ duration: VesilaDuration) {
        update { $0.selectDuration(duration, now: now()) }
    }

    /// Right-click: turn everything off, or restore the last combination that was on.
    func quickToggle() {
        setVesilaActive(!state.isSessionActive)
    }

    /// Master switch: restore the last combination or pause the current Scheduled window.
    func setVesilaActive(_ isOn: Bool) {
        guard isOn != state.isSessionActive else { return }
        guard isOn else {
            cancelPendingPresenceActivation()
            update { $0.turnOffByUser(now: now(), calendar: calendar()) }
            return
        }
        var features = state.preferences.lastActiveFeatures
        let presenceNeedsAccess = features.presence && !isAccessibilityGranted()
        if presenceNeedsAccess {
            features.presence = false
        }
        if !features.isEmpty {
            update { $0.setActiveFeatures(features, now: now(), calendar: calendar()) }
        }
        if presenceNeedsAccess {
            onAccessibilityRequired?()
            // A Presence-only restore leaves the session off; reset the clicked master switch.
            onChange?(state)
        }
    }

    /// System end: turns both main features off without creating a pause. Also abandons a
    /// pending Presence activation. Every interruption abandons it too in `handleInterruption(_:)`,
    /// including a lock that keeps the session. User ends take the separate override path.
    func turnOff() {
        cancelPendingPresenceActivation()
        update { $0.turnOff() }
    }

    /// Polls, because macOS posts no notification for this, and turns Presence on as soon as
    /// Accessibility is granted. Gives up after three minutes.
    func activatePresenceWhenAccessibilityGranted() {
        cancelPendingPresenceActivation()
        let deadline = Date.now.addingTimeInterval(Self.accessibilityGrantTimeout)
        accessibilityGrantTimer = .scheduledOnMain(interval: 1, repeats: true, owner: self) { controller in
            if controller.isAccessibilityGranted() {
                controller.cancelPendingPresenceActivation()
                controller.setPresenceActive(true)
            } else if Date.now >= deadline {
                controller.cancelPendingPresenceActivation()
            }
        }
    }

    /// Called by `InterruptionMonitor`; internal so tests can drive lock and lid close, which can't
    /// be posted in-process. Every interruption first abandons a pending Presence activation, so
    /// nothing switches on by itself afterwards. An ignored lock then returns before `update(_:)`,
    /// so state, services, and the expiration timer are left exactly as they were.
    func handleInterruption(_ interruption: VesilaInterruption) {
        cancelPendingPresenceActivation()
        switch interruption {
        case .screenLocked: screenLocked = true
        case .sessionResigned: sessionInactive = true
        case .systemSleep: sleeping = true
        case .lidClosed: lidClosed = true
        }
        guard state.shouldEndSession(for: interruption) else {
            Logger.vesila.info("Staying active after interruption: \(interruption.rawValue, privacy: .public) (Stay Active When Locked is on)")
            return
        }
        Logger.vesila.info("Turning off after interruption: \(interruption.rawValue, privacy: .public)")
        update { $0.turnOff() }
    }

    /// Called at quit: stops observing the system and releases everything.
    func shutdown() {
        interruptionMonitor.stop()
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        turnOff()
    }

    func selectActivationMode(_ mode: VesilaActivationMode) {
        update {
            $0.selectActivationMode(mode, now: now(), calendar: calendar(),
                                    canActivate: canScheduleActivate, canUsePresence: isAccessibilityGranted())
        }
        rescheduleBoundary()
    }

    func setSchedule(_ schedule: VesilaSchedule) {
        update {
            $0.setSchedule(schedule, now: now(), calendar: calendar(),
                           canActivate: canScheduleActivate, canUsePresence: isAccessibilityGranted())
        }
        rescheduleBoundary()
    }

    /// Internal hooks let tests drive resume events and boundaries with an injected clock.
    func handleResume(_ event: VesilaResume) {
        switch event {
        case .screenUnlocked: screenLocked = false
        case .sessionActivated: sessionInactive = false
        case .systemWake:
            sleeping = false
            let session = sessionSnapshot()
            screenLocked = session.locked
            sessionInactive = !session.active
        case .lidOpened: lidClosed = false
        case .clockChanged: break
        }
        evaluateSchedule()
    }

    func evaluateSchedule() {
        // Manual resume events leave state, services, and rendering untouched.
        guard state.preferences.activationMode == .scheduled else { return }
        update {
            $0.evaluateSchedule(now: now(), calendar: calendar(),
                                canActivate: canScheduleActivate, canUsePresence: isAccessibilityGranted())
        }
        rescheduleBoundary()
    }

    private func rescheduleBoundary() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        guard state.preferences.activationMode == .scheduled,
              let date = state.preferences.schedule.nextBoundary(after: now(), calendar: calendar()) else { return }
        scheduleTimer = .scheduledOnMain(interval: max(0.1, date.timeIntervalSince(now())), repeats: false, owner: self) {
            $0.evaluateSchedule()
        }
    }

    // MARK: - State changes

    private func update(_ transition: (inout VesilaState) -> Void) {
        let previous = state
        transition(&state)
        reconcileServices(with: previous)
        if state.preferences != previous.preferences {
            preferencesStore.save(state.preferences)
        }
        onChange?(state)
    }

    /// Makes the services match `state`. Each service call is idempotent.
    private func reconcileServices(with previous: VesilaState) {
        let systemAwakeHeld = powerAssertions.update(preventSystemSleep: state.activeFeatures.systemAwake)
        if !systemAwakeHeld {
            // Never show System Awake as on without an assertion actually backing it.
            Logger.vesila.error("System Awake could not create its power assertion; leaving it off.")
            state.setSystemAwake(false, now: now(), calendar: calendar(), userInitiated: false)
        }

        presenceKeeper.setActive(state.activeFeatures.presence)

        if state.expirationDate != previous.expirationDate {
            scheduleExpiration(at: state.expirationDate)
        }
    }

    private func scheduleExpiration(at date: Date?) {
        expirationTimer?.invalidate()
        expirationTimer = nil
        guard let date else { return }
        expirationTimer = .scheduledOnMain(interval: max(0.1, date.timeIntervalSince(now())), repeats: false, owner: self) { controller in
            controller.turnOff()
        }
    }

    /// Presence can't pulse without Accessibility, so it must not stay on once the permission is
    /// revoked. This is the normal Presence-off transition: System Awake and its session carry on.
    private func turnPresenceOffAfterAccessibilityRevoked() {
        guard state.activeFeatures.presence else { return }
        Logger.vesila.error("Accessibility access was revoked; turning Presence off.")
        update { $0.setPresence(false, now: now(), calendar: calendar(), userInitiated: false) }
    }

    private func cancelPendingPresenceActivation() {
        accessibilityGrantTimer?.invalidate()
        accessibilityGrantTimer = nil
    }
}

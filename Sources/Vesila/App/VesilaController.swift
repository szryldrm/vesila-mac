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
/// means no expiration timer; launch and every interruption leave both main features off.
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
    private var expirationTimer: Timer?
    private var accessibilityGrantTimer: Timer?

    /// `presenceKeeper` is only passed by tests, to drive its polls directly.
    init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        isAccessibilityGranted: @escaping () -> Bool = { AccessibilityPermission.isGranted },
        presenceKeeper: PresenceKeeper? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.isAccessibilityGranted = isAccessibilityGranted
        self.presenceKeeper = presenceKeeper ?? PresenceKeeper(isAccessibilityGranted: isAccessibilityGranted)
        state = VesilaState(preferences: preferencesStore.load())

        self.presenceKeeper.onAccessibilityRevoked = { [weak self] in
            self?.turnPresenceOffAfterAccessibilityRevoked()
        }
        interruptionMonitor.start { [weak self] interruption in
            Logger.vesila.info("Turning off after interruption: \(interruption.rawValue, privacy: .public)")
            self?.turnOff()
        }
    }

    // MARK: - Intents

    func setPresenceActive(_ isOn: Bool) {
        guard !isOn || isAccessibilityGranted() else {
            onAccessibilityRequired?()
            // The toggle already flipped itself on click; re-render so it shows the real state.
            onChange?(state)
            return
        }
        update { $0.setPresence(isOn, now: .now) }
    }

    func setSystemAwakeActive(_ isOn: Bool) {
        update { $0.setSystemAwake(isOn, now: .now) }
    }

    func setKeepDisplayAwake(_ isOn: Bool) {
        update { $0.setKeepDisplayAwake(isOn) }
    }

    func selectDuration(_ duration: VesilaDuration) {
        update { $0.selectDuration(duration, now: .now) }
    }

    /// Right-click: turn everything off, or restore the last combination that was on.
    func quickToggle() {
        guard !state.isSessionActive else {
            turnOff()
            return
        }
        var features = state.preferences.lastActiveFeatures
        let presenceNeedsAccess = features.presence && !isAccessibilityGranted()
        if presenceNeedsAccess {
            features.presence = false
        }
        if !features.isEmpty {
            update { $0.setActiveFeatures(features, now: .now) }
        }
        if presenceNeedsAccess {
            onAccessibilityRequired?()
        }
    }

    /// Turns both main features off. Also abandons a pending Presence activation, so nothing
    /// switches back on by itself after right-click-off, expiration, sleep, lock, or lid close.
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

    /// Called at quit: stops observing the system and releases everything.
    func shutdown() {
        interruptionMonitor.stop()
        turnOff()
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
        let systemAwakeHeld = powerAssertions.update(
            preventSystemSleep: state.activeFeatures.systemAwake,
            preventDisplaySleep: state.preventsDisplaySleep
        )
        if !systemAwakeHeld {
            // Never show System Awake as on without an assertion actually backing it.
            Logger.vesila.error("System Awake could not create its power assertion; leaving it off.")
            state.setSystemAwake(false, now: .now)
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
        expirationTimer = .scheduledOnMain(interval: max(0.1, date.timeIntervalSinceNow), repeats: false, owner: self) { controller in
            controller.turnOff()
        }
    }

    /// Presence can't pulse without Accessibility, so it must not stay on once the permission is
    /// revoked. This is the normal Presence-off transition: System Awake and its session carry on.
    private func turnPresenceOffAfterAccessibilityRevoked() {
        guard state.activeFeatures.presence else { return }
        Logger.vesila.error("Accessibility access was revoked; turning Presence off.")
        update { $0.setPresence(false, now: .now) }
    }

    private func cancelPendingPresenceActivation() {
        accessibilityGrantTimer?.invalidate()
        accessibilityGrantTimer = nil
    }
}

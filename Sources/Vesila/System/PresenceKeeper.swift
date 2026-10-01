import CoreGraphics
import Foundation
import OSLog

/// Keeps apps like Microsoft Teams from marking the user Away while they're at the Mac but not
/// typing, e.g. reading or thinking.
///
/// After `realIdleThreshold` of real inactivity it posts one synthetic mouse-move, then another
/// every `pulseInterval` for as long as the user stays idle. Real input restarts the idle period.
/// Vesila's own pulses never count as real input (see `UserIdleMonitor`).
@MainActor
final class PresenceKeeper {
    static let realIdleThreshold: TimeInterval = 4 * 60
    static let pulseInterval: TimeInterval = 3 * 60
    private static let pollInterval: TimeInterval = 15

    /// Called from a poll that finds Accessibility no longer granted. Presence can't work without it,
    /// so the owner turns Presence off, which also stops the polling.
    var onAccessibilityRevoked: (() -> Void)?

    private let idleMonitor: UserIdleMonitor
    private let isAccessibilityGranted: () -> Bool
    private let sendPulse: @MainActor () -> Bool
    private var pollTimer: Timer?
    private var nextPulseDue: Date?
    private var isInPulseFailureStreak = false

    init(
        idleMonitor: UserIdleMonitor = UserIdleMonitor(),
        isAccessibilityGranted: @escaping () -> Bool = { AccessibilityPermission.isGranted },
        sendPulse: @escaping @MainActor () -> Bool = ActivityPulse.post
    ) {
        self.idleMonitor = idleMonitor
        self.isAccessibilityGranted = isAccessibilityGranted
        self.sendPulse = sendPulse
    }

    func setActive(_ active: Bool) {
        guard active != (pollTimer != nil) else { return }
        nextPulseDue = nil
        isInPulseFailureStreak = false
        if active {
            idleMonitor.reset(at: .now)
            pollTimer = .scheduledOnMain(interval: Self.pollInterval, repeats: true, tolerance: Self.pollInterval * 0.2, owner: self) { keeper in
                keeper.tick(at: .now)
            }
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    func tick(at now: Date) {
        // Checked on every poll, not just before a pulse, so a revocation is noticed within seconds.
        guard isAccessibilityGranted() else {
            onAccessibilityRevoked?()
            return
        }
        guard idleMonitor.secondsSinceRealInput(at: now) >= Self.realIdleThreshold else {
            nextPulseDue = nil
            return
        }
        if let nextPulseDue, now < nextPulseDue {
            return
        }
        if sendPulse() {
            idleMonitor.noteSyntheticPulse(at: now)
            isInPulseFailureStreak = false
        } else {
            // Retried every interval; logged once per run of failures, not on every retry.
            if !isInPulseFailureStreak {
                Logger.vesila.error("Presence pulse could not be posted; retrying every \(Int(Self.pulseInterval)) s.")
            }
            isInPulseFailureStreak = true
        }
        nextPulseDue = now.addingTimeInterval(Self.pulseInterval)
    }
}

/// Measures how long the user has really been idle, ignoring Vesila's own pulses.
///
/// The system idle clock also counts the synthetic mouse-move. That's the point, since it's what
/// Teams watches, but it means the clock alone can't tell a pulse from real input. Inspecting
/// individual events would need an event tap and the Input Monitoring permission. Instead, when
/// the latest input lines up with our last pulse, it's attributed to the pulse and idle time keeps
/// counting from the last real input.
final class UserIdleMonitor {
    /// `kCGAnyInputEventType` (~0) isn't imported into Swift. Don't substitute `.null`: that
    /// reports the time since a null event (effectively since login), so every check looked idle
    /// and real activity was never seen. The unwrap can't fail: imported C enums accept any raw value.
    static let anyInputEventType = CGEventType(rawValue: ~0)!

    private static let pulseAttributionWindow: TimeInterval = 1

    private let secondsSinceLastInput: () -> TimeInterval
    private var lastRealInput: Date
    private var lastSyntheticPulse: Date?

    init(now: Date = .now, secondsSinceLastInput: @escaping () -> TimeInterval = UserIdleMonitor.systemSecondsSinceLastInput) {
        self.secondsSinceLastInput = secondsSinceLastInput
        lastRealInput = now
    }

    static func systemSecondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }

    func reset(at now: Date) {
        lastRealInput = now
        lastSyntheticPulse = nil
    }

    func noteSyntheticPulse(at now: Date) {
        lastSyntheticPulse = now
    }

    func secondsSinceRealInput(at now: Date) -> TimeInterval {
        let systemIdle = secondsSinceLastInput()
        let lastInput = now.addingTimeInterval(-systemIdle)
        if let lastSyntheticPulse, abs(lastInput.timeIntervalSince(lastSyntheticPulse)) < Self.pulseAttributionWindow {
            return now.timeIntervalSince(lastRealInput)
        }
        lastRealInput = lastInput
        return systemIdle
    }
}

/// Posts Presence's pulse: a mouse-move to where the cursor already is. No click, scroll, or
/// keystroke, and the cursor doesn't visibly move. Requires Accessibility.
enum ActivityPulse {
    /// Stored in `eventSourceUserData` so Vesila's events are identifiable when inspecting event streams.
    private static let marker: Int64 = 0x51501

    static func post() -> Bool {
        guard AccessibilityPermission.isGranted,
              let source = CGEventSource(stateID: .hidSystemState),
              // Never fall back to a made-up position: that would visibly move the cursor.
              let cursorLocation = CGEvent(source: source)?.location,
              let event = CGEvent(
                  mouseEventSource: source,
                  mouseType: .mouseMoved,
                  mouseCursorPosition: cursorLocation,
                  mouseButton: .left
              )
        else { return false }

        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
        return true
    }
}

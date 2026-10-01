import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import Vesila

/// The parts of macOS Presence depends on: the idle clock (time since the last input event of any
/// kind) and the Accessibility permission.
private final class SimulatedSystem {
    var now: Date
    var lastInput: Date
    var accessibilityGranted = true

    init(start: Date) {
        now = start
        lastInput = start
    }

    var secondsSinceLastInput: TimeInterval { now.timeIntervalSince(lastInput) }
}

/// Drives `PresenceKeeper` through simulated time, one tick per 15 s poll like the real timer.
/// The user's last real input is at t = 0.
@MainActor
private final class PresenceSimulation {
    private static let pollInterval: TimeInterval = 15

    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let clock: SimulatedSystem
    let idleMonitor: UserIdleMonitor
    private(set) var keeper: PresenceKeeper!
    private(set) var pulseAttempts: [TimeInterval] = []
    private(set) var pulses: [TimeInterval] = []
    private(set) var revocationReports: [TimeInterval] = []
    var pulsesSucceed = true

    /// `pulsesResetSystemIdleClock` models whether macOS counts the synthetic mouse-move as input.
    /// Vesila must pulse on the same schedule either way.
    init(pulsesResetSystemIdleClock: Bool = true) {
        let clock = SimulatedSystem(start: start)
        self.clock = clock
        idleMonitor = UserIdleMonitor(now: start) { clock.secondsSinceLastInput }
        keeper = PresenceKeeper(idleMonitor: idleMonitor, isAccessibilityGranted: { clock.accessibilityGranted }) { [unowned self] in
            pulseAttempts.append(elapsed)
            guard pulsesSucceed else { return false }
            pulses.append(elapsed)
            if pulsesResetSystemIdleClock {
                clock.lastInput = clock.now
            }
            return true
        }
        keeper.onAccessibilityRevoked = { [unowned self] in
            revocationReports.append(elapsed)
        }
    }

    var elapsed: TimeInterval { clock.now.timeIntervalSince(start) }

    /// Real idle time as Vesila computes it at the current simulated time.
    var realIdle: TimeInterval { idleMonitor.secondsSinceRealInput(at: clock.now) }

    /// Ticks every 15 s up to `seconds`, with real keyboard/mouse input at the given offsets.
    func run(until seconds: TimeInterval, userInputAt inputs: [TimeInterval] = []) {
        while elapsed + Self.pollInterval <= seconds {
            let next = elapsed + Self.pollInterval
            for input in inputs where input > elapsed && input <= next {
                clock.lastInput = start.addingTimeInterval(input)
            }
            clock.now = start.addingTimeInterval(next)
            keeper.tick(at: clock.now)
        }
    }
}

@Suite("Presence timing")
@MainActor
struct PresenceKeeperTests {
    @Test(arguments: [true, false])
    func firstPulseAfterFourIdleMinutesThenEveryThree(pulsesResetSystemIdleClock: Bool) {
        let simulation = PresenceSimulation(pulsesResetSystemIdleClock: pulsesResetSystemIdleClock)
        simulation.run(until: 800)
        #expect(simulation.pulses == [240, 420, 600, 780])
    }

    @Test func noPulsesWhileTheUserIsActive() {
        let simulation = PresenceSimulation()
        simulation.run(until: 3600, userInputAt: Array(stride(from: 60.0, through: 3600, by: 60)))
        #expect(simulation.pulseAttempts.isEmpty)
    }

    @Test func pulsesAreNotMistakenForRealInput() {
        let simulation = PresenceSimulation()
        simulation.run(until: 300)
        #expect(simulation.pulses == [240])
        #expect(simulation.clock.secondsSinceLastInput == 60, "the system, and Teams, saw activity at the pulse")
        #expect(simulation.realIdle == 300, "Vesila still knows the user has been idle since t = 0")
    }

    @Test func realInputRestartsTheIdlePeriod() {
        let simulation = PresenceSimulation()
        simulation.run(until: 1000, userInputAt: [500])
        #expect(simulation.pulses == [240, 420, 750, 930])
    }

    @Test func aFailedPulseIsRetriedOneIntervalLater() {
        let simulation = PresenceSimulation()
        simulation.pulsesSucceed = false
        simulation.run(until: 450)
        #expect(simulation.pulseAttempts == [240, 420])
        #expect(simulation.pulses.isEmpty)
    }

    /// Regression guard: `.null` measures time since login, which made every check look idle.
    @Test func idleClockCountsAnyInputEvent() {
        #expect(UserIdleMonitor.anyInputEventType.rawValue == UInt32.max)
        #expect(UserIdleMonitor.anyInputEventType != .null)
    }

    @Test func revokedAccessibilityIsReportedAtTheNextPollInsteadOfPulsing() {
        let simulation = PresenceSimulation()
        simulation.run(until: 400)
        #expect(simulation.pulses == [240])
        #expect(simulation.revocationReports.isEmpty)

        simulation.clock.accessibilityGranted = false
        simulation.run(until: 700)
        #expect(simulation.revocationReports.first == 405, "noticed at the first poll after revocation")
        #expect(simulation.pulseAttempts == [240], "no pulse is attempted without Accessibility")
    }
}

@Suite("Accessibility request")
struct AccessibilityRequestTests {
    /// `requestAccess()` must ask with the prompt option; that is what registers Vesila with macOS.
    @Test func promptOptionKeyMatchesTheSystemConstant() {
        #expect(AccessibilityPermission.promptOptionKey == kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String)
    }
}

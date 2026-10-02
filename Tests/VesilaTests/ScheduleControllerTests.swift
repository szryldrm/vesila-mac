import AppKit
import Testing
@testable import Vesila

@Suite("Scheduled controller wiring", .serialized)
@MainActor
struct ScheduleControllerTests {
    private func makeController(_ defaults: UserDefaults, now: @escaping () -> Date,
                                session: @escaping () -> (locked: Bool, active: Bool) = { (false, true) }) -> VesilaController {
        PreferencesStore(defaults: defaults).save(VesilaPreferences(
            lastActiveFeatures: MainFeatures(systemAwake: true), activationMode: .scheduled
        ))
        return VesilaController(preferencesStore: PreferencesStore(defaults: defaults),
                                isAccessibilityGranted: { false }, now: now,
                                calendar: { scheduleCalendar }, sessionSnapshot: session)
    }

    @Test func launchAndBoundaryTimersActivateAndExpireWithoutPause() throws {
        try withTemporaryDefaults { defaults in
            var now = scheduleDate(hour: 8, minute: 50)
            let controller = makeController(defaults, now: { now })
            defer { controller.shutdown() }
            #expect(!controller.state.isSessionActive)
            let boundary = try #require(controller.scheduleTimer)
            now = scheduleDate(hour: 9)
            boundary.fire()
            #expect(controller.state.isSessionActive)
            #expect(controller.state.expirationDate == scheduleDate(hour: 18))
            #expect(controller.scheduleTimer !== boundary)
            #expect(!boundary.isValid)
            let expiration = try #require(controller.expirationTimer)
            now = scheduleDate(hour: 18)
            expiration.fire()
            #expect(!controller.state.isSessionActive)
            #expect(controller.state.preferences.pausedWindowDay == nil)
            controller.evaluateSchedule()
            #expect(!controller.state.isSessionActive)
        }
    }

    @Test func launchWithinWindowStartsAndShutdownDoesNotPause() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults, now: { scheduleDate(hour: 10) })
            #expect(controller.state.isSessionActive)
            #expect(controller.state.expirationDate == scheduleDate(hour: 18))
            controller.shutdown()
            #expect(controller.scheduleTimer == nil)
            #expect(controller.expirationTimer == nil)
            #expect(controller.state.preferences.pausedWindowDay == nil)
        }
    }

    @Test func wakeWaitsForUnlockAndUserSessionBeforeActivating() {
        withTemporaryDefaults { defaults in
            var now = scheduleDate(hour: 8, minute: 50)
            var locked = false
            var active = true
            let controller = makeController(defaults, now: { now }, session: { (locked, active) })
            defer { controller.shutdown() }
            controller.handleInterruption(.systemSleep)
            controller.handleInterruption(.sessionResigned)
            now = scheduleDate(hour: 9, minute: 30)
            locked = true
            active = false
            controller.handleResume(.systemWake)
            #expect(!controller.state.isSessionActive)
            controller.evaluateSchedule() // a boundary while locked cannot start
            #expect(!controller.state.isSessionActive)
            controller.handleResume(.screenUnlocked)
            #expect(!controller.state.isSessionActive) // session still inactive
            controller.handleResume(.sessionActivated)
            #expect(controller.state.isSessionActive)
            #expect(controller.state.expirationDate == scheduleDate(hour: 18))
            #expect(controller.state.preferences.pausedWindowDay == nil)
        }
    }

    @Test func lockedLaunchAndIgnoredLockNeverCreateNewSessions() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults, now: { scheduleDate(hour: 10) }, session: { (true, true) })
            defer { controller.shutdown() }
            #expect(!controller.state.isSessionActive)
            controller.handleResume(.screenUnlocked)
            #expect(controller.state.isSessionActive)
            controller.setStayActiveWhenLocked(true)
            let before = controller.state
            let timer = controller.expirationTimer
            controller.handleInterruption(.screenLocked)
            #expect(controller.state == before)
            #expect(controller.expirationTimer === timer)
            controller.turnOff() // system end while locked
            controller.evaluateSchedule()
            #expect(!controller.state.isSessionActive)
        }
    }

    @Test func lockAndLidInterruptionsReevaluateOnResumeWithoutOverride() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults, now: { scheduleDate(hour: 10) })
            defer { controller.shutdown() }
            controller.handleInterruption(.screenLocked)
            #expect(!controller.state.isSessionActive)
            #expect(controller.state.preferences.pausedWindowDay == nil)
            controller.handleResume(.screenUnlocked)
            #expect(controller.state.isSessionActive)
            controller.handleInterruption(.lidClosed)
            controller.evaluateSchedule()
            #expect(!controller.state.isSessionActive)
            controller.handleResume(.lidOpened)
            #expect(controller.state.isSessionActive)
            #expect(controller.state.preferences.pausedWindowDay == nil)
        }
    }

    @Test(arguments: ["master", "rightClick", "feature"])
    func userOffSurvivesWakeAndUnlockAndUserOnResumes(path: String) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults, now: { scheduleDate(hour: 10) })
            defer { controller.shutdown() }
            switch path {
            case "master": controller.setVesilaActive(false)
            case "rightClick": controller.quickToggle()
            default: controller.setSystemAwakeActive(false)
            }
            #expect(controller.state.preferences.pausedWindowDay != nil)
            controller.handleInterruption(.screenLocked)
            controller.handleResume(.systemWake)
            controller.handleResume(.screenUnlocked)
            #expect(!controller.state.isSessionActive)
            #expect(PreferencesStore(defaults: defaults).load().pausedWindowDay == controller.state.preferences.pausedWindowDay)
            controller.quickToggle()
            #expect(controller.state.isSessionActive)
            #expect(controller.state.preferences.pausedWindowDay == nil)
            #expect(controller.state.expirationDate == scheduleDate(hour: 18))
        }
    }

    @Test func modeAndEditReplaceTimersAndClockChangeEndsMovedSession() {
        withTemporaryDefaults { defaults in
            var now = scheduleDate(hour: 10)
            let controller = makeController(defaults, now: { now })
            defer { controller.shutdown() }
            let timer = controller.scheduleTimer
            controller.setSchedule(VesilaSchedule(endMinute: 16 * 60))
            #expect(controller.state.expirationDate == scheduleDate(hour: 16))
            #expect(controller.scheduleTimer !== timer)
            now = scheduleDate(hour: 17)
            NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
            #expect(!controller.state.isSessionActive)
            #expect(controller.state.preferences.pausedWindowDay == nil)
            controller.selectActivationMode(.manual)
            #expect(controller.scheduleTimer == nil)
            controller.setSystemAwakeActive(true)
            #expect(controller.state.expirationDate == scheduleDate(hour: 18))
            controller.selectActivationMode(.scheduled)
            #expect(controller.state.isSessionActive)
            #expect(controller.state.expirationDate == nil)
        }
    }
}

import Foundation
import Testing
@testable import Vesila

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

private func minutes(_ value: Double) -> TimeInterval { value * 60 }

@Suite("Session lifecycle")
struct SessionLifecycleTests {
    @Test func launchStartsWithBothMainFeaturesOff() {
        let state = VesilaState(preferences: VesilaPreferences(lastActiveFeatures: .both))
        #expect(state.activeFeatures == .none)
        #expect(!state.isSessionActive)
        #expect(state.expirationDate == nil)
    }

    @Test func sessionStartsWhenTheFirstFeatureTurnsOn() {
        var state = VesilaState()
        state.setSystemAwake(true, now: t0)
        #expect(state.isSessionActive)
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(60)))
    }

    @Test func enablingTheSecondFeatureDoesNotRestartTheSession() {
        var state = VesilaState()
        state.setPresence(true, now: t0)
        state.setSystemAwake(true, now: t0.addingTimeInterval(minutes(10)))
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(60)))
    }

    @Test func disablingOneFeatureWhileTheOtherStaysOnDoesNotRestartTheSession() {
        var state = VesilaState()
        state.setActiveFeatures(.both, now: t0)
        state.setPresence(false, now: t0.addingTimeInterval(minutes(15)))
        #expect(state.isSessionActive)
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(60)))
    }

    @Test func bothOffEndsTheSessionAndTheNextOneStartsFresh() {
        var state = VesilaState()
        state.setPresence(true, now: t0)
        state.setPresence(false, now: t0.addingTimeInterval(minutes(5)))
        #expect(!state.isSessionActive)
        #expect(state.expirationDate == nil)

        let restart = t0.addingTimeInterval(minutes(30))
        state.setPresence(true, now: restart)
        #expect(state.expirationDate == restart.addingTimeInterval(minutes(60)))
    }

    @Test func turnOffEndsEverything() {
        var state = VesilaState()
        state.setActiveFeatures(.both, now: t0)
        state.turnOff()
        #expect(state.activeFeatures == .none)
        #expect(state.expirationDate == nil)
        #expect(state.remainingTime(at: t0) == nil)
    }
}

@Suite("Active-for duration")
struct DurationTests {
    @Test func changingDurationDuringASessionRestartsTheCountdownFromNow() {
        var state = VesilaState()
        state.setPresence(true, now: t0)
        let later = t0.addingTimeInterval(minutes(40))
        state.selectDuration(.thirtyMinutes, now: later)
        #expect(state.expirationDate == later.addingTimeInterval(minutes(30)))
    }

    @Test func reselectingTheCurrentDurationAlsoRestartsTheCountdown() {
        var state = VesilaState()
        state.setPresence(true, now: t0)
        let later = t0.addingTimeInterval(minutes(20))
        state.selectDuration(.oneHour, now: later)
        #expect(state.expirationDate == later.addingTimeInterval(minutes(60)))
    }

    @Test func untilTurnedOffRemovesTheExpiration() {
        var state = VesilaState()
        state.setSystemAwake(true, now: t0)
        state.selectDuration(.untilTurnedOff, now: t0.addingTimeInterval(60))
        #expect(state.isSessionActive)
        #expect(state.expirationDate == nil)
        #expect(state.remainingTime(at: t0) == nil)
    }

    @Test func untilTurnedOffSessionsNeverGetAnExpiration() {
        var state = VesilaState(preferences: VesilaPreferences(duration: .untilTurnedOff))
        state.setActiveFeatures(.both, now: t0)
        #expect(state.expirationDate == nil)
    }

    @Test func choosingADurationWhileInactiveOnlyStoresIt() {
        var state = VesilaState()
        state.selectDuration(.fiveHours, now: t0)
        #expect(!state.isSessionActive)
        #expect(state.expirationDate == nil)

        state.setPresence(true, now: t0.addingTimeInterval(minutes(1)))
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(1) + minutes(300)))
    }

    @Test func remainingTimeCountsDownAndClampsAtZero() {
        var state = VesilaState(preferences: VesilaPreferences(duration: .thirtyMinutes))
        state.setPresence(true, now: t0)
        #expect(state.remainingTime(at: t0.addingTimeInterval(minutes(10))) == minutes(20))
        #expect(state.remainingTime(at: t0.addingTimeInterval(minutes(45))) == 0)
    }
}

@Suite("Right-click memory")
struct QuickToggleMemoryTests {
    @Test func firstRunRemembersBothFeatures() {
        #expect(VesilaState().preferences.lastActiveFeatures == .both)
    }

    @Test func remembersTheLatestNonEmptyCombination() {
        var state = VesilaState()
        state.setPresence(true, now: t0)
        #expect(state.preferences.lastActiveFeatures == MainFeatures(presence: true, systemAwake: false))

        state.setSystemAwake(true, now: t0)
        state.setPresence(false, now: t0)
        #expect(state.preferences.lastActiveFeatures == MainFeatures(presence: false, systemAwake: true))

        // Turning the last feature off, or turning everything off, keeps the memory.
        state.setSystemAwake(false, now: t0)
        #expect(state.preferences.lastActiveFeatures == MainFeatures(presence: false, systemAwake: true))
        state.setActiveFeatures(.both, now: t0)
        state.turnOff()
        #expect(state.preferences.lastActiveFeatures == .both)
    }
}

@Suite("Stay Active When Locked")
struct StayActiveWhenLockedTests {
    private func activeSession(stayActiveWhenLocked: Bool) -> VesilaState {
        var state = VesilaState(preferences: VesilaPreferences(stayActiveWhenLocked: stayActiveWhenLocked))
        state.setActiveFeatures(.both, now: t0)
        return state
    }

    /// What `VesilaController.handleInterruption(_:)` does to the state: ask the rule once, and
    /// end the session through the normal `turnOff()` only when it says so.
    private func interrupt(_ state: inout VesilaState, with interruption: VesilaInterruption) {
        if state.shouldEndSession(for: interruption) {
            state.turnOff()
        }
    }

    @Test func isOffByDefault() {
        #expect(!VesilaPreferences().stayActiveWhenLocked)
        #expect(!VesilaState().preferences.stayActiveWhenLocked)
    }

    @Test(arguments: [MainFeatures.none, .both,
                      MainFeatures(presence: true, systemAwake: false),
                      MainFeatures(presence: false, systemAwake: true)], [true, false])
    func availabilityDependsOnlyOnSystemAwake(features: MainFeatures, storedChoice: Bool) {
        var state = VesilaState(preferences: VesilaPreferences(stayActiveWhenLocked: storedChoice))
        state.setActiveFeatures(features, now: t0)
        #expect(state.isStayActiveWhenLockedAvailable == features.systemAwake)
    }

    @Test(arguments: [true, false])
    func presenceOnlySessionsEndOnLock(storedChoice: Bool) {
        var state = VesilaState(preferences: VesilaPreferences(stayActiveWhenLocked: storedChoice))
        state.setPresence(true, now: t0)
        #expect(state.shouldEndSession(for: .screenLocked))
        interrupt(&state, with: .screenLocked)
        #expect(state.activeFeatures == .none)
        #expect(state.expirationDate == nil)
        #expect(state.preferences.stayActiveWhenLocked == storedChoice)
    }

    @Test(arguments: [true, false])
    func systemAwakeChangesKeepTheStoredChoice(storedChoice: Bool) {
        var state = VesilaState(preferences: VesilaPreferences(stayActiveWhenLocked: storedChoice))
        state.setActiveFeatures(.both, now: t0)
        let expiration = state.expirationDate
        state.setSystemAwake(false, now: t0.addingTimeInterval(60))
        #expect(!state.isStayActiveWhenLockedAvailable)
        #expect(state.preferences.stayActiveWhenLocked == storedChoice)
        #expect(state.shouldEndSession(for: .screenLocked))
        state.setSystemAwake(true, now: t0.addingTimeInterval(120))
        #expect(state.isStayActiveWhenLockedAvailable)
        #expect(state.preferences.stayActiveWhenLocked == storedChoice)
        #expect(state.shouldEndSession(for: .screenLocked) == !storedChoice)
        #expect(state.expirationDate == expiration)
    }

    @Test func changingItNeverTouchesTheSession() {
        var state = VesilaState()
        state.setStayActiveWhenLocked(true)
        #expect(!state.isSessionActive)
        #expect(state.expirationDate == nil)

        state.setPresence(true, now: t0)
        state.setStayActiveWhenLocked(false)
        state.setStayActiveWhenLocked(true)
        #expect(state.activeFeatures == MainFeatures(presence: true, systemAwake: false))
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(60)))
        #expect(state.preferences.lastActiveFeatures == MainFeatures(presence: true, systemAwake: false),
                "it is not part of what right-click restores")
    }

    @Test func aLockWithTheSettingOffEndsTheSession() {
        var state = activeSession(stayActiveWhenLocked: false)
        #expect(state.shouldEndSession(for: .screenLocked))
        // Mutating calls can't go inside `#expect`, so the session is ended first.
        state.turnOff()
        #expect(state.activeFeatures == .none)
        #expect(!state.isSessionActive)
        #expect(state.expirationDate == nil)
    }

    @Test func aLockWithTheSettingOnKeepsTheSession() {
        var state = activeSession(stayActiveWhenLocked: true)
        let beforeLock = state
        #expect(!state.shouldEndSession(for: .screenLocked))
        interrupt(&state, with: .screenLocked)
        #expect(state == beforeLock)
        #expect(state.activeFeatures == .both)
        #expect(state.activeFeatures.presence, "an active Presence stays on")
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(60)))
    }

    /// The full interruption rule across all feature combinations and stored choices.
    @Test(arguments: [VesilaInterruption.systemSleep, .screenLocked, .sessionResigned, .lidClosed], [true, false])
    func onlyALockWithTheSettingOnAndSystemAwakeKeepsTheSession(interruption: VesilaInterruption, stayActiveWhenLocked: Bool) {
        for features in [MainFeatures.none, .both,
                         MainFeatures(presence: true, systemAwake: false),
                         MainFeatures(presence: false, systemAwake: true)] {
            var state = VesilaState(preferences: VesilaPreferences(stayActiveWhenLocked: stayActiveWhenLocked))
            state.setActiveFeatures(features, now: t0)
            let keepsSession = interruption == .screenLocked && stayActiveWhenLocked && features.systemAwake
            #expect(state.shouldEndSession(for: interruption) == !keepsSession)
        }
    }

    @Test(arguments: [VesilaInterruption.systemSleep, .lidClosed, .sessionResigned], [true, false])
    func sleepLidCloseAndUserSwitchAlwaysEndTheSession(interruption: VesilaInterruption, stayActiveWhenLocked: Bool) {
        var state = activeSession(stayActiveWhenLocked: stayActiveWhenLocked)
        #expect(state.shouldEndSession(for: interruption))
        interrupt(&state, with: interruption)
        #expect(state.activeFeatures == .none)
        #expect(state.expirationDate == nil)
        #expect(state.preferences.stayActiveWhenLocked == stayActiveWhenLocked, "the preference itself is kept")
    }

    /// Vesila has no unlock transition: the only way back on is an explicit intent. Further locks
    /// (the monitor never reports an unlock) leave an ended session ended and a kept one untouched.
    @Test(arguments: [true, false])
    func nothingIsRestoredAfterALock(stayActiveWhenLocked: Bool) {
        var state = activeSession(stayActiveWhenLocked: stayActiveWhenLocked)
        interrupt(&state, with: .screenLocked)
        let afterLock = state
        interrupt(&state, with: .screenLocked)
        #expect(state == afterLock)
        #expect(state.isSessionActive == stayActiveWhenLocked)
    }

    /// Only the countdown itself; the controller tests fire the real expiration timer after a lock.
    @Test func anIgnoredLockNeitherPausesNorRestartsTheCountdown() {
        var state = VesilaState(preferences: VesilaPreferences(stayActiveWhenLocked: true, duration: .thirtyMinutes))
        state.setActiveFeatures(.both, now: t0)
        interrupt(&state, with: .screenLocked)
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(30)), "the lock neither pauses nor restarts it")
        #expect(state.remainingTime(at: t0.addingTimeInterval(minutes(20))) == minutes(10))
        #expect(state.remainingTime(at: t0.addingTimeInterval(minutes(45))) == 0)
    }
}

@Suite("Status line")
struct StatusLineTests {
    @Test func describesEachSessionState() {
        var state = VesilaState()
        #expect(VesilaFormatter.statusLine(for: state, at: t0) == "Inactive")

        state.setPresence(true, now: t0)
        #expect(VesilaFormatter.statusLine(for: state, at: t0) == "1h 0m remaining")
        #expect(VesilaFormatter.statusLine(for: state, at: t0.addingTimeInterval(minutes(59))) == "1m remaining")
        #expect(VesilaFormatter.statusLine(for: state, at: t0.addingTimeInterval(minutes(60) - 5)) == "5s remaining")

        state.selectDuration(.untilTurnedOff, now: t0)
        #expect(VesilaFormatter.statusLine(for: state, at: t0) == "Until turned off")
    }

    @Test(arguments: [
        (0.0, "0s remaining"),
        (59.4, "59s remaining"),
        (59.6, "1m remaining"),
        (125.0, "2m remaining"),
        (3725.0, "1h 2m remaining"),
        (5 * 3600.0, "5h 0m remaining")
    ])
    func formatsRemainingTime(seconds: TimeInterval, expected: String) {
        #expect(VesilaFormatter.remainingDescription(seconds) == expected)
    }
}

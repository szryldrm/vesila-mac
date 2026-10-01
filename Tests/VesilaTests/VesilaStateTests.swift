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

@Suite("Keep Display Awake")
struct KeepDisplayAwakeTests {
    @Test func onlyPreventsDisplaySleepTogetherWithSystemAwake() {
        var state = VesilaState(preferences: VesilaPreferences(keepDisplayAwake: true))
        #expect(!state.preventsDisplaySleep)

        state.setPresence(true, now: t0)
        #expect(!state.preventsDisplaySleep)

        state.setSystemAwake(true, now: t0)
        #expect(state.preventsDisplaySleep)

        state.setSystemAwake(false, now: t0)
        #expect(!state.preventsDisplaySleep)
        #expect(state.preferences.keepDisplayAwake, "the preference is remembered while System Awake is off")
    }

    @Test func respectsThePreferenceWhileSystemAwakeIsOn() {
        var state = VesilaState()
        state.setSystemAwake(true, now: t0)
        state.setKeepDisplayAwake(false)
        #expect(!state.preventsDisplaySleep)
        state.setKeepDisplayAwake(true)
        #expect(state.preventsDisplaySleep)
    }

    @Test func doesNotAffectTheSession() {
        var state = VesilaState()
        state.setKeepDisplayAwake(false)
        #expect(!state.isSessionActive)

        state.setSystemAwake(true, now: t0)
        state.setKeepDisplayAwake(true)
        #expect(state.expirationDate == t0.addingTimeInterval(minutes(60)))
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

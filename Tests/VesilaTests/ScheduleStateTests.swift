import Foundation
import Testing
@testable import Vesila

@Suite("Scheduled state transitions")
struct ScheduleStateTests {
    private func scheduled(features: MainFeatures = .both) -> VesilaState {
        VesilaState(preferences: VesilaPreferences(lastActiveFeatures: features, activationMode: .scheduled))
    }

    private func evaluate(_ state: inout VesilaState, at date: Date, canActivate: Bool = true, presence: Bool = true) {
        state.evaluateSchedule(now: date, calendar: scheduleCalendar, canActivate: canActivate, canUsePresence: presence)
    }

    @Test func restoresOnceAndExpiresAtWindowEndWithoutPause() {
        var state = scheduled()
        evaluate(&state, at: scheduleDate(hour: 9))
        #expect(state.activeFeatures == .both)
        #expect(state.expirationDate == scheduleDate(hour: 18))
        let active = state
        evaluate(&state, at: scheduleDate(hour: 12))
        #expect(state == active)
        state.turnOff() // expiration's system end
        evaluate(&state, at: scheduleDate(hour: 18))
        #expect(!state.isSessionActive)
        #expect(state.preferences.pausedWindowDay == nil)
        evaluate(&state, at: scheduleDate(7, hour: 9))
        #expect(state.isSessionActive)
        state.turnOff()
        evaluate(&state, at: scheduleDate(10, hour: 12))
        #expect(!state.isSessionActive)
    }

    @Test(arguments: [MainFeatures.both, MainFeatures(presence: false, systemAwake: true)])
    func accessibilityFilteringMatchesMasterRestore(features: MainFeatures) {
        var state = scheduled(features: features)
        evaluate(&state, at: scheduleDate(hour: 10), presence: false)
        #expect(state.activeFeatures == MainFeatures(presence: false, systemAwake: features.systemAwake))
        #expect(state.expirationDate == (features.systemAwake ? scheduleDate(hour: 18) : nil))
        if !features.systemAwake { #expect(state.preferences.lastActiveFeatures == features) }
    }

    @Test func activationAvailabilityBlocksNewSessionsButKeepsAnAdoptedSession() {
        var state = scheduled()
        evaluate(&state, at: scheduleDate(hour: 9), canActivate: false)
        #expect(!state.isSessionActive)
        evaluate(&state, at: scheduleDate(hour: 10))
        let active = state
        evaluate(&state, at: scheduleDate(hour: 11), canActivate: false)
        #expect(state == active) // ignored lock with Stay Active When Locked
    }

    @Test func masterOffPausesOnlyTodayAndOnClearsPause() {
        var state = scheduled()
        evaluate(&state, at: scheduleDate(hour: 9))
        state.turnOffByUser(now: scheduleDate(hour: 10), calendar: scheduleCalendar)
        #expect(state.preferences.pausedWindowDay == scheduleCalendar.startOfDay(for: scheduleDate(hour: 10)))
        evaluate(&state, at: scheduleDate(hour: 13))
        #expect(!state.isSessionActive)
        // A relaunch doesn't lose the pause.
        var relaunched = VesilaState(preferences: state.preferences)
        evaluate(&relaunched, at: scheduleDate(hour: 13))
        #expect(!relaunched.isSessionActive)
        state.setActiveFeatures(.both, now: scheduleDate(hour: 14), calendar: scheduleCalendar)
        #expect(state.preferences.pausedWindowDay == nil)
        #expect(state.expirationDate == scheduleDate(hour: 18))
        state.turnOffByUser(now: scheduleDate(hour: 15), calendar: scheduleCalendar)
        evaluate(&state, at: scheduleDate(7, hour: 9))
        #expect(state.isSessionActive)
        #expect(state.expirationDate == scheduleDate(7, hour: 18))
    }

    @Test func systemAwakeOffPausesAndOnResumes() {
        var state = scheduled()
        evaluate(&state, at: scheduleDate(hour: 9))
        state.setSystemAwake(false, now: scheduleDate(hour: 10), calendar: scheduleCalendar)
        #expect(state.activeFeatures == .none)
        #expect(state.pausedWindow(at: scheduleDate(hour: 11), calendar: scheduleCalendar) != nil)
        state.setPresence(true, now: scheduleDate(hour: 11), calendar: scheduleCalendar)
        evaluate(&state, at: scheduleDate(hour: 12))
        #expect(state.activeFeatures == .none)
        state.setSystemAwake(true, now: scheduleDate(hour: 14), calendar: scheduleCalendar)
        #expect(state.preferences.pausedWindowDay == nil)
        #expect(state.expirationDate == scheduleDate(hour: 18))
    }

    @Test func changingOneFeatureKeepsWindowAndDoesNotPause() {
        var state = scheduled()
        evaluate(&state, at: scheduleDate(hour: 9))
        state.setPresence(false, now: scheduleDate(hour: 10), calendar: scheduleCalendar)
        evaluate(&state, at: scheduleDate(hour: 12))
        #expect(state.activeFeatures == MainFeatures(systemAwake: true))
        #expect(state.expirationDate == scheduleDate(hour: 18))
        #expect(state.preferences.pausedWindowDay == nil)
    }

    @Test func systemEndsNeverPauseAndResumeMayReactivate() {
        var state = scheduled(features: .both)
        evaluate(&state, at: scheduleDate(hour: 9))
        state.setPresence(false, now: scheduleDate(hour: 10), calendar: scheduleCalendar, userInitiated: false)
        #expect(state.preferences.pausedWindowDay == nil)
        evaluate(&state, at: scheduleDate(hour: 11))
        #expect(state.isSessionActive)
        state.turnOff() // sleep/lock/lid/switch/quit
        #expect(state.preferences.pausedWindowDay == nil)
        evaluate(&state, at: scheduleDate(hour: 12))
        #expect(state.isSessionActive)
        state.setSystemAwake(true, now: scheduleDate(hour: 13), calendar: scheduleCalendar)
        state.setPresence(false, now: scheduleDate(hour: 13), calendar: scheduleCalendar, userInitiated: false)
        state.setSystemAwake(false, now: scheduleDate(hour: 13), calendar: scheduleCalendar, userInitiated: false)
        #expect(state.preferences.pausedWindowDay == nil)
    }

    @Test func outsideSessionIsUnlimitedAndWindowAdoptsItsFeatures() {
        var state = scheduled()
        state.setSystemAwake(true, now: scheduleDate(5, hour: 20), calendar: scheduleCalendar)
        #expect(state.expirationDate == nil)
        evaluate(&state, at: scheduleDate(hour: 8))
        #expect(state.isSessionActive)
        #expect(state.expirationDate == nil)
        evaluate(&state, at: scheduleDate(hour: 9))
        #expect(state.activeFeatures == MainFeatures(systemAwake: true))
        #expect(state.expirationDate == scheduleDate(hour: 18))
        evaluate(&state, at: scheduleDate(hour: 18))
        #expect(!state.isSessionActive)
        #expect(state.preferences.pausedWindowDay == nil)
    }

    @Test func switchingModesAdoptsOrRemovesCountdownAndRestartsManualDuration() {
        var state = VesilaState()
        state.setActiveFeatures(.both, now: scheduleDate(hour: 10))
        state.selectActivationMode(.scheduled, now: scheduleDate(hour: 11), calendar: scheduleCalendar, canActivate: true)
        #expect(state.activeFeatures == .both)
        #expect(state.expirationDate == scheduleDate(hour: 18))
        state.selectActivationMode(.manual, now: scheduleDate(hour: 12), calendar: scheduleCalendar, canActivate: true)
        #expect(state.expirationDate == scheduleDate(hour: 13))
        state.selectActivationMode(.scheduled, now: scheduleDate(hour: 20), calendar: scheduleCalendar, canActivate: true)
        #expect(state.isSessionActive)
        #expect(state.expirationDate == nil)
        state.selectDuration(.twoHours, now: scheduleDate(hour: 20))
        #expect(state.expirationDate == nil)
    }

    @Test func inactiveModeSwitchOnlyActivatesInsideAvailableScheduledWindow() {
        var state = VesilaState()
        state.selectActivationMode(.scheduled, now: scheduleDate(hour: 8), calendar: scheduleCalendar, canActivate: true)
        #expect(!state.isSessionActive)
        state.selectActivationMode(.manual, now: scheduleDate(hour: 10), calendar: scheduleCalendar, canActivate: true)
        #expect(!state.isSessionActive)
        state.selectActivationMode(.scheduled, now: scheduleDate(hour: 10), calendar: scheduleCalendar, canActivate: false)
        #expect(!state.isSessionActive)
        evaluate(&state, at: scheduleDate(hour: 10))
        #expect(state.isSessionActive)
    }

    @Test func editsReevaluateAndPauseSurvivesSameDayEdits() {
        var state = scheduled()
        evaluate(&state, at: scheduleDate(hour: 10))
        state.setSchedule(VesilaSchedule(startMinute: 11 * 60), now: scheduleDate(hour: 10), calendar: scheduleCalendar, canActivate: true)
        #expect(!state.isSessionActive)
        #expect(state.preferences.pausedWindowDay == nil)
        state.setSchedule(VesilaSchedule(endMinute: 17 * 60), now: scheduleDate(hour: 10), calendar: scheduleCalendar, canActivate: true)
        #expect(state.expirationDate == scheduleDate(hour: 17))
        state.turnOffByUser(now: scheduleDate(hour: 10), calendar: scheduleCalendar)
        let pause = state.preferences.pausedWindowDay
        state.setSchedule(VesilaSchedule(startMinute: 8 * 60, endMinute: 16 * 60), now: scheduleDate(hour: 10), calendar: scheduleCalendar, canActivate: true)
        #expect(state.preferences.pausedWindowDay == pause)
        #expect(!state.isSessionActive)
        let beforeInvalidEdit = state
        state.setSchedule(VesilaSchedule(days: []), now: scheduleDate(hour: 10), calendar: scheduleCalendar, canActivate: true)
        #expect(state == beforeInvalidEdit)
    }
}

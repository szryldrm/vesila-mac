import Foundation
import Testing
@testable import Vesila

@Suite("Preferences persistence")
struct PreferencesStoreTests {
    @Test func freshInstallUsesDefaults() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            let preferences = store.load()
            #expect(!preferences.stayActiveWhenLocked, "Stay Active When Locked is off by default")
            #expect(preferences.duration == .oneHour)
            #expect(preferences.lastActiveFeatures == .both)
            #expect(!store.isOnboardingCompleted)
        }
    }

    @Test func roundTrips() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            let preferences = VesilaPreferences(
                stayActiveWhenLocked: true,
                duration: .threeHours,
                lastActiveFeatures: MainFeatures(presence: false, systemAwake: true)
            )
            store.save(preferences)
            #expect(store.load() == preferences)
        }
    }

    @Test func stayActiveWhenLockedCanBeTurnedBackOff() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            store.save(VesilaPreferences(stayActiveWhenLocked: true))
            #expect(store.load().stayActiveWhenLocked)
            store.save(VesilaPreferences(stayActiveWhenLocked: false))
            #expect(!store.load().stayActiveWhenLocked)
        }
    }

    /// Keep Display Awake was a different setting: its stored value, whichever way it was set,
    /// must never become Stay Active When Locked.
    @Test(arguments: [true, false])
    func neverCarriesOverTheOldKeepDisplayAwakeValue(oldValue: Bool) {
        withTemporaryDefaults { defaults in
            defaults.set(oldValue, forKey: "keepDisplayAwake")
            let store = PreferencesStore(defaults: defaults)
            #expect(!store.load().stayActiveWhenLocked)

            store.save(store.load())
            #expect(defaults.object(forKey: "stayActiveWhenLocked") as? Bool == false)
        }
    }

    @Test func noLongerWritesKeepDisplayAwake() {
        withTemporaryDefaults { defaults in
            PreferencesStore(defaults: defaults).save(VesilaPreferences(stayActiveWhenLocked: true))
            #expect(defaults.object(forKey: "keepDisplayAwake") == nil)
            #expect(defaults.object(forKey: "stayActiveWhenLocked") as? Bool == true)
        }
    }

    /// Existing installs must keep their settings: these keys were written by earlier versions.
    @Test func readsValuesWrittenByEarlierVersions() {
        withTemporaryDefaults { defaults in
            defaults.set("twoHours", forKey: "selectedDuration")
            defaults.set(true, forKey: "lastEnabledConfiguration.hasValue")
            defaults.set(true, forKey: "lastEnabledConfiguration.presence")
            defaults.set(false, forKey: "lastEnabledConfiguration.systemAwake")
            defaults.set(true, forKey: "onboardingCompleted")

            let store = PreferencesStore(defaults: defaults)
            #expect(store.load() == VesilaPreferences(
                duration: .twoHours,
                lastActiveFeatures: MainFeatures(presence: true, systemAwake: false)
            ))
            #expect(store.isOnboardingCompleted)
        }
    }

    @Test func ignoresUnusableStoredValues() {
        withTemporaryDefaults { defaults in
            defaults.set("fortnight", forKey: "selectedDuration")
            defaults.set(true, forKey: "lastEnabledConfiguration.hasValue")
            defaults.set(false, forKey: "lastEnabledConfiguration.presence")
            defaults.set(false, forKey: "lastEnabledConfiguration.systemAwake")

            let preferences = PreferencesStore(defaults: defaults).load()
            #expect(preferences.duration == .oneHour)
            #expect(preferences.lastActiveFeatures == .both, "an empty combination must never be restored")
        }
    }

    @Test func onboardingCompletesOnlyWhenMarked() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            store.save(VesilaPreferences())
            #expect(!store.isOnboardingCompleted)
            store.markOnboardingCompleted()
            #expect(store.isOnboardingCompleted)
        }
    }
    @Test func scheduledPreferencesAndPauseRoundTripAndClear() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            let preferences = VesilaPreferences(
                activationMode: .scheduled,
                schedule: VesilaSchedule(days: [1, 3, 7], startMinute: 480, endMinute: 1020),
                pausedWindowDay: scheduleCalendar.startOfDay(for: scheduleDate(hour: 10))
            )
            store.save(preferences)
            #expect(store.load() == preferences)
            #expect(defaults.string(forKey: "activationMode") == "scheduled")
            #expect(defaults.array(forKey: "schedule.days") as? [Int] == [1, 3, 7])
            #expect(defaults.integer(forKey: "schedule.startMinute") == 480)
            #expect(defaults.integer(forKey: "schedule.endMinute") == 1020)
            var cleared = preferences
            cleared.pausedWindowDay = nil
            store.save(cleared)
            #expect(store.load() == cleared)
            #expect(defaults.object(forKey: "schedule.pausedWindowDay") == nil)
        }
    }

    @Test func missingScheduleKeysDefaultToManualWeekdays() {
        withTemporaryDefaults { defaults in
            let preferences = PreferencesStore(defaults: defaults).load()
            #expect(preferences.activationMode == .manual)
            #expect(preferences.schedule == VesilaSchedule())
            #expect(preferences.pausedWindowDay == nil)
        }
    }

    @Test(arguments: [
        VesilaSchedule(days: []), VesilaSchedule(days: [0, 8]),
        VesilaSchedule(startMinute: -1), VesilaSchedule(endMinute: 1440),
        VesilaSchedule(startMinute: 1080, endMinute: 540)
    ])
    func corruptSchedulesFallBackAsAWhole(schedule: VesilaSchedule) {
        withTemporaryDefaults { defaults in
            defaults.set("unknown", forKey: "activationMode")
            defaults.set(schedule.days.sorted(), forKey: "schedule.days")
            defaults.set(schedule.startMinute, forKey: "schedule.startMinute")
            defaults.set(schedule.endMinute, forKey: "schedule.endMinute")
            defaults.set("not a date", forKey: "schedule.pausedWindowDay")
            #expect(PreferencesStore(defaults: defaults).load() == VesilaPreferences())
        }
    }

    @Test func wrongTypesAndPartiallyMissingScheduleFallBack() {
        withTemporaryDefaults { defaults in
            defaults.set([2, 3], forKey: "schedule.days")
            defaults.set(480, forKey: "schedule.startMinute")
            #expect(PreferencesStore(defaults: defaults).load().schedule == VesilaSchedule())
            defaults.set("evening", forKey: "schedule.endMinute")
            #expect(PreferencesStore(defaults: defaults).load().schedule == VesilaSchedule())
            defaults.set(["Monday"], forKey: "schedule.days")
            defaults.set(1020, forKey: "schedule.endMinute")
            #expect(PreferencesStore(defaults: defaults).load().schedule == VesilaSchedule())
        }
    }

}

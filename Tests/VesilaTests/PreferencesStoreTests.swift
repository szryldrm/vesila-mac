import Foundation
import Testing
@testable import Vesila

@Suite("Preferences persistence")
struct PreferencesStoreTests {
    @Test func freshInstallUsesDefaults() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            let preferences = store.load()
            #expect(preferences.keepDisplayAwake)
            #expect(preferences.duration == .oneHour)
            #expect(preferences.lastActiveFeatures == .both)
            #expect(!store.isOnboardingCompleted)
        }
    }

    @Test func roundTrips() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            let preferences = VesilaPreferences(
                keepDisplayAwake: false,
                duration: .threeHours,
                lastActiveFeatures: MainFeatures(presence: false, systemAwake: true)
            )
            store.save(preferences)
            #expect(store.load() == preferences)
        }
    }

    /// Existing installs must keep their settings: these keys were written by earlier versions.
    @Test func readsValuesWrittenByEarlierVersions() {
        withTemporaryDefaults { defaults in
            defaults.set("twoHours", forKey: "selectedDuration")
            defaults.set(false, forKey: "keepDisplayAwake")
            defaults.set(true, forKey: "lastEnabledConfiguration.hasValue")
            defaults.set(true, forKey: "lastEnabledConfiguration.presence")
            defaults.set(false, forKey: "lastEnabledConfiguration.systemAwake")
            defaults.set(true, forKey: "onboardingCompleted")

            let store = PreferencesStore(defaults: defaults)
            #expect(store.load() == VesilaPreferences(
                keepDisplayAwake: false,
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
}

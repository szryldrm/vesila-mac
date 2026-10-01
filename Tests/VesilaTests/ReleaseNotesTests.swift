import Foundation
import Testing
@testable import Vesila

@Suite("ReleaseNotes")
struct ReleaseNotesTests {
    private let entries = ["1.0.9", "1.0.3", "1.0.10", "1.0.4", "1.0.11"].map {
        ReleaseNotes(version: $0, notes: ["Changes in \($0)"])
    }

    @Test func freshInstallAndIncompleteOnboardingShowNothing() {
        #expect(show(previous: nil, onboarded: false).isEmpty)
        #expect(show(previous: "1.0.2", onboarded: false).isEmpty)
    }

    @Test func preFeatureUpgradeShowsOnlyCurrentVersion() {
        #expect(show(previous: nil) == ["1.0.10"])
    }

    @Test func normalUpgradeUsesNumericOrdering() {
        #expect(show(previous: "1.0.9") == ["1.0.10"])
    }

    @Test func skippedUpdatesShowAllIncludedVersionsNewestFirst() {
        #expect(show(previous: "1.0.3") == ["1.0.10", "1.0.9", "1.0.4"])
    }

    @Test func sameVersionAndDowngradeShowNothing() {
        #expect(show(previous: "1.0.10").isEmpty)
        #expect(show(previous: "1.0.11").isEmpty)
    }

    @Test func developmentRunsShowNothing() {
        #expect(show(previous: nil, current: "dev").isEmpty)
        #expect(show(previous: "1.0.9", current: "dev").isEmpty)
    }

    @Test func noMatchingEntryShowsNothing() {
        #expect(show(previous: nil, current: "2.0.0").isEmpty)
        #expect(show(previous: "1.0.5", current: "1.0.6").isEmpty)
        #expect(ReleaseNotes.entriesToShow(previousVersion: "1.0.2", currentVersion: "1.0.3",
            isOnboardingCompleted: true, entries: []).isEmpty)
    }

    @Test func missingAndMalformedDataAreIgnored() {
        #expect(ReleaseNotes.decode(nil).isEmpty)
        #expect(ReleaseNotes.decode(Data("invalid".utf8)).isEmpty)
        #expect(ReleaseNotes.decode(Data("[{\"version\":\"1.0.3\"}]".utf8)).isEmpty)
    }

    @Test func bundledNotesDecodeSuccessfully() {
        let bundled = ReleaseNotes.loadBundled()
        #expect(!bundled.isEmpty, "ReleaseNotes.json should decode successfully")
        for entry in bundled {
            #expect(entry.version.split(separator: ".").allSatisfy { Int($0) != nil },
                "Bundled entry version \(entry.version) is not valid")
            #expect(!entry.notes.isEmpty, "Bundled entry \(entry.version) should contain at least one note")
            #expect(entry.notes.allSatisfy { !$0.isEmpty })
        }
        if VesilaConfig.version != "dev" {
            let latest = bundled.max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
            #expect(latest?.version == VesilaConfig.version,
                "Latest bundled release note should match the current app version")
        }
    }

    @Test func recordedVersionRoundTripsAcrossStoreInstances() {
        withTemporaryDefaults { defaults in
            let store = PreferencesStore(defaults: defaults)
            #expect(store.lastLaunchedVersion == nil)
            store.lastLaunchedVersion = "1.0.9"
            #expect(defaults.string(forKey: "lastLaunchedVersion") == "1.0.9")
            let reloaded = PreferencesStore(defaults: defaults)
            #expect(reloaded.lastLaunchedVersion == "1.0.9")
            reloaded.lastLaunchedVersion = "1.0.10"
            #expect(store.lastLaunchedVersion == "1.0.10")
            store.lastLaunchedVersion = nil
            #expect(reloaded.lastLaunchedVersion == nil)
        }
    }

    private func show(previous: String?, current: String = "1.0.10", onboarded: Bool = true) -> [String] {
        ReleaseNotes.entriesToShow(previousVersion: previous, currentVersion: current,
            isOnboardingCompleted: onboarded, entries: entries).map(\.version)
    }
}

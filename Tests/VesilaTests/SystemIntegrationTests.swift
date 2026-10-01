import AppKit
import Testing
@testable import Vesila

/// These use real IOKit power assertions (briefly held by the test process) and real
/// in-process workspace notifications. Serialized because they count this process's assertions.
@Suite("Power assertions and controller wiring", .serialized)
@MainActor
struct SystemIntegrationTests {
    private func makeController(defaults: UserDefaults, accessibilityGranted: @escaping () -> Bool = { false }) -> VesilaController {
        VesilaController(preferencesStore: PreferencesStore(defaults: defaults), isAccessibilityGranted: accessibilityGranted)
    }

    // MARK: PowerAssertionService

    @Test func systemAwakeHoldsOnlyTheSystemAssertion() {
        let service = PowerAssertionService()
        #expect(service.update(preventSystemSleep: true, preventDisplaySleep: false))
        #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
        service.releaseAll()
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
    }

    @Test func displayAssertionOnlyExistsAlongsideTheSystemAssertion() {
        let service = PowerAssertionService()
        service.update(preventSystemSleep: false, preventDisplaySleep: true)
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)

        service.update(preventSystemSleep: true, preventDisplaySleep: true)
        #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [displaySleepAssertionType, systemSleepAssertionType])

        service.update(preventSystemSleep: false, preventDisplaySleep: true)
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
    }

    @Test func repeatedCallsNeitherLeakNorDoubleRelease() {
        let service = PowerAssertionService()
        for _ in 0..<3 {
            service.update(preventSystemSleep: true, preventDisplaySleep: true)
        }
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().count == 2)
        for _ in 0..<3 {
            service.releaseAll()
        }
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
    }

    @Test func deallocationReleasesAssertions() {
        do {
            let service = PowerAssertionService()
            service.update(preventSystemSleep: true, preventDisplaySleep: true)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().count == 2)
        }
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
    }

    // MARK: VesilaController

    @Test func launchesWithEverythingOffEvenWhenACombinationIsRemembered() {
        withTemporaryDefaults { defaults in
            PreferencesStore(defaults: defaults).save(VesilaPreferences(lastActiveFeatures: .both))
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }
            #expect(controller.state.activeFeatures == .none)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
        }
    }

    @Test func systemAwakeWorksWithoutAccessibility() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }
            controller.setSystemAwakeActive(true)
            #expect(controller.state.activeFeatures == MainFeatures(presence: false, systemAwake: true))
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [displaySleepAssertionType, systemSleepAssertionType])

            controller.setSystemAwakeActive(false)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
        }
    }

    @Test func keepDisplayAwakeIsSubordinateAndRemembered() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }

            controller.setKeepDisplayAwake(false)
            controller.setSystemAwakeActive(true)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])

            controller.setKeepDisplayAwake(true)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [displaySleepAssertionType, systemSleepAssertionType])

            controller.setSystemAwakeActive(false)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
            #expect(controller.state.preferences.keepDisplayAwake)
            #expect(PreferencesStore(defaults: defaults).load().keepDisplayAwake)
        }
    }

    @Test func presenceRequiresAccessibility() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }
            var prompts = 0
            var renders = 0
            controller.onAccessibilityRequired = { prompts += 1 }
            controller.onChange = { _ in renders += 1 }

            controller.setPresenceActive(true)
            #expect(controller.state.activeFeatures == .none)
            #expect(prompts == 1)
            #expect(renders == 1, "the UI re-renders so the clicked toggle snaps back")
        }
    }

    @Test func rightClickTurnsOffAndRestoresTheLastCombination() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }

            controller.quickToggle()
            #expect(controller.state.activeFeatures == .both, "first run restores both")

            controller.setPresenceActive(false)
            controller.quickToggle()
            #expect(controller.state.activeFeatures == .none)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)

            controller.quickToggle()
            #expect(controller.state.activeFeatures == MainFeatures(presence: false, systemAwake: true))
        }
    }

    @Test func rightClickRestoresWhatItCanAndAsksForAccessibility() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }
            var prompts = 0
            controller.onAccessibilityRequired = { prompts += 1 }

            controller.quickToggle()
            #expect(controller.state.activeFeatures == MainFeatures(presence: false, systemAwake: true))
            #expect(prompts == 1)
        }
    }

    @Test(arguments: [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification])
    func sleepAndUserSwitchTurnEverythingOff(notification: Notification.Name) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.quickToggle()
            #expect(controller.state.isSessionActive)

            NSWorkspace.shared.notificationCenter.post(name: notification, object: nil)
            #expect(controller.state.activeFeatures == .none)
            #expect(controller.state.expirationDate == nil)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
        }
    }

    @Test func preferencesSurviveARelaunchButActiveFeaturesDoNot() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            controller.selectDuration(.twoHours)
            controller.setSystemAwakeActive(true)
            controller.shutdown()
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty, "quit releases everything")

            let relaunched = makeController(defaults: defaults)
            defer { relaunched.shutdown() }
            #expect(relaunched.state.activeFeatures == .none)
            #expect(relaunched.state.preferences.duration == .twoHours)
            #expect(relaunched.state.preferences.lastActiveFeatures == MainFeatures(presence: false, systemAwake: true))
        }
    }

    @Test func revokingAccessibilityTurnsPresenceOffButLeavesSystemAwakeAlone() {
        withTemporaryDefaults { defaults in
            var granted = true
            let presenceKeeper = PresenceKeeper(
                idleMonitor: UserIdleMonitor(secondsSinceLastInput: { 0 }),
                isAccessibilityGranted: { granted },
                sendPulse: { true }
            )
            let controller = VesilaController(
                preferencesStore: PreferencesStore(defaults: defaults),
                isAccessibilityGranted: { granted },
                presenceKeeper: presenceKeeper
            )
            defer { controller.shutdown() }
            var renders = 0
            controller.onChange = { _ in renders += 1 }

            controller.quickToggle()
            #expect(controller.state.activeFeatures == .both)
            let expiration = controller.state.expirationDate

            granted = false
            presenceKeeper.tick(at: .now)
            #expect(controller.state.activeFeatures == MainFeatures(presence: false, systemAwake: true))
            #expect(controller.state.expirationDate == expiration, "the session is not restarted")
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [displaySleepAssertionType, systemSleepAssertionType])
            let rendersAfterRevocation = renders
            #expect(rendersAfterRevocation == 2, "one render to turn on, one to turn Presence off")

            presenceKeeper.tick(at: .now)
            #expect(renders == rendersAfterRevocation, "handled once, not again on later polls")
            #expect(controller.state.activeFeatures == MainFeatures(presence: false, systemAwake: true))
        }
    }

    @Test func pendingPresenceActivationCompletesOnceAccessibilityIsGranted() {
        withTemporaryDefaults { defaults in
            var granted = false
            let controller = makeController(defaults: defaults, accessibilityGranted: { granted })
            defer { controller.shutdown() }

            controller.activatePresenceWhenAccessibilityGranted()
            granted = true
            RunLoop.main.run(until: .now + 1.5)
            #expect(controller.state.activeFeatures.presence)
        }
    }

    @Test func anInterruptionAbandonsAPendingPresenceActivation() {
        withTemporaryDefaults { defaults in
            var granted = false
            let controller = makeController(defaults: defaults, accessibilityGranted: { granted })
            defer { controller.shutdown() }

            controller.activatePresenceWhenAccessibilityGranted()
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            granted = true
            RunLoop.main.run(until: .now + 1.5)
            #expect(!controller.state.isSessionActive, "Vesila must stay off after sleep, even if access arrives later")
        }
    }
}

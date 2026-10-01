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
        #expect(service.update(preventSystemSleep: true))
        #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
        #expect(!vesilaPowerAssertionTypesHeldByThisProcess().contains(displaySleepAssertionType))

        #expect(service.update(preventSystemSleep: false))
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
    }

    @Test func repeatedCallsNeitherLeakNorDoubleRelease() {
        let service = PowerAssertionService()
        for _ in 0..<3 {
            service.update(preventSystemSleep: true)
        }
        #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
        for _ in 0..<3 {
            service.releaseAll()
        }
        #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
    }

    @Test func deallocationReleasesAssertions() {
        do {
            let service = PowerAssertionService()
            service.update(preventSystemSleep: true)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
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
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])

            controller.setSystemAwakeActive(false)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
        }
    }

    /// Keep Display Awake is gone: System Awake never keeps the display on, whatever the new setting.
    @Test(arguments: [true, false])
    func systemAwakeNeverHoldsADisplayAssertion(stayActiveWhenLocked: Bool) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(stayActiveWhenLocked)
            controller.setSystemAwakeActive(true)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
            #expect(!vesilaPowerAssertionTypesHeldByThisProcess().contains(displaySleepAssertionType))

            controller.setStayActiveWhenLocked(!stayActiveWhenLocked)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
        }
    }

    // MARK: Stay Active When Locked

    @Test func stayActiveWhenLockedIsOffByDefaultAndSurvivesARelaunch() {
        withTemporaryDefaults { defaults in
            // A value left behind by Keep Display Awake must not be carried over.
            defaults.set(true, forKey: "keepDisplayAwake")

            let controller = makeController(defaults: defaults)
            #expect(!controller.state.preferences.stayActiveWhenLocked)
            controller.setStayActiveWhenLocked(true)
            controller.shutdown()

            let relaunched = makeController(defaults: defaults)
            #expect(relaunched.state.preferences.stayActiveWhenLocked)
            #expect(relaunched.state.activeFeatures == .none, "the setting never starts a session")
            relaunched.setStayActiveWhenLocked(false)
            relaunched.shutdown()

            let relaunchedAgain = makeController(defaults: defaults)
            defer { relaunchedAgain.shutdown() }
            #expect(!relaunchedAgain.state.preferences.stayActiveWhenLocked)
        }
    }

    @Test(arguments: [true, false])
    func presenceOnlyLockEndsTheSessionWhateverTheStoredChoice(storedChoice: Bool) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(storedChoice)
            controller.setPresenceActive(true)
            controller.handleInterruption(.screenLocked)
            #expect(controller.state.activeFeatures == .none)
            #expect(controller.state.expirationDate == nil)
            #expect(controller.expirationTimer == nil)
            #expect(controller.state.preferences.stayActiveWhenLocked == storedChoice)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
        }
    }

    @Test(arguments: [true, false])
    func systemAwakeChangesAndRelaunchKeepTheLockPreference(storedChoice: Bool) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            controller.setStayActiveWhenLocked(storedChoice)
            var renderedAvailability: [Bool] = []
            controller.onChange = { renderedAvailability.append($0.isStayActiveWhenLockedAvailable) }
            controller.setSystemAwakeActive(true)
            controller.setSystemAwakeActive(false)
            #expect(controller.state.preferences.stayActiveWhenLocked == storedChoice)
            #expect(PreferencesStore(defaults: defaults).load().stayActiveWhenLocked == storedChoice)
            controller.setSystemAwakeActive(true)
            #expect(controller.state.preferences.stayActiveWhenLocked == storedChoice)
            #expect(renderedAvailability == [true, false, true])
            controller.setSystemAwakeActive(false)
            controller.shutdown()

            let relaunched = makeController(defaults: defaults)
            defer { relaunched.shutdown() }
            #expect(relaunched.state.preferences.stayActiveWhenLocked == storedChoice)
            #expect(!relaunched.state.isStayActiveWhenLockedAvailable)
            relaunched.setSystemAwakeActive(true)
            #expect(relaunched.state.isStayActiveWhenLockedAvailable)
            #expect(relaunched.state.shouldEndSession(for: .screenLocked) == !storedChoice)
        }
    }

    @Test func changingStayActiveWhenLockedLeavesTheSessionAlone() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.quickToggle()
            let expiration = controller.state.expirationDate

            controller.setStayActiveWhenLocked(true)
            #expect(controller.state.activeFeatures == .both)
            #expect(controller.state.expirationDate == expiration)
            #expect(controller.state.preferences.lastActiveFeatures == .both)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
        }
    }

    @Test func aLockWithStayActiveWhenLockedOffTurnsEverythingOff() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.quickToggle()
            #expect(controller.state.activeFeatures == .both)

            controller.handleInterruption(.screenLocked)
            #expect(controller.state.activeFeatures == .none)
            #expect(controller.state.expirationDate == nil)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
        }
    }

    @Test func aLockWithStayActiveWhenLockedOnChangesNothing() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(true)
            controller.quickToggle()
            let beforeLock = controller.state
            var renders = 0
            controller.onChange = { _ in renders += 1 }

            controller.handleInterruption(.screenLocked)
            #expect(controller.state == beforeLock)
            #expect(controller.state.activeFeatures == .both)
            #expect(controller.state.expirationDate == beforeLock.expirationDate)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
            // No render means `update(_:)` never ran, so services and the expiration timer were not touched.
            #expect(renders == 0)
        }
    }

    /// Vesila observes no unlock or wake event, so nothing is restored or restarted afterwards. The
    /// real unlock notification is system-wide (distributed), so it isn't posted from a test; the
    /// in-process "coming back" notifications are, and time is allowed to pass.
    @Test(arguments: [true, false])
    func nothingIsRestoredOrRestartedAfterALock(stayActiveWhenLocked: Bool) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(stayActiveWhenLocked)
            controller.quickToggle()
            controller.handleInterruption(.screenLocked)
            let afterLock = controller.state
            var renders = 0
            controller.onChange = { _ in renders += 1 }

            let workspaceCenter = NSWorkspace.shared.notificationCenter
            for notification in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
                workspaceCenter.post(name: notification, object: nil)
            }
            RunLoop.main.run(until: .now + 0.5)

            #expect(controller.state == afterLock)
            #expect(renders == 0)
            #expect(controller.state.isSessionActive == stayActiveWhenLocked)
            let expectedAssertions: [String] = stayActiveWhenLocked ? [systemSleepAssertionType] : []
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == expectedAssertions)
        }
    }

    /// The expiration timer survives an ignored lock untouched, and its own callback still ends the
    /// session. Durations are at least 30 minutes, so the real timer is fired rather than waited
    /// for; `Timer.fire()` runs its block synchronously on this (main) thread.
    @Test func theExpirationTimerSurvivesAnIgnoredLockAndEndsTheSession() throws {
        try withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(true)
            controller.selectDuration(.thirtyMinutes)
            controller.setSystemAwakeActive(true)
            let expiration = try #require(controller.state.expirationDate)
            let timer = try #require(controller.expirationTimer)

            controller.handleInterruption(.screenLocked)
            #expect(controller.expirationTimer === timer, "the lock neither cancels nor reschedules it")
            #expect(timer.isValid)
            #expect(abs(timer.fireDate.timeIntervalSince(expiration)) < 1)
            #expect(controller.state.expirationDate == expiration)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])

            timer.fire()
            #expect(controller.state.activeFeatures == .none)
            #expect(controller.state.expirationDate == nil)
            #expect(controller.expirationTimer == nil)
            #expect(!timer.isValid)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
            #expect(controller.state.preferences.stayActiveWhenLocked, "expiry ends the session, not the setting")
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

    @Test(arguments: [MainFeatures.both, MainFeatures(presence: true, systemAwake: false), MainFeatures(presence: false, systemAwake: true)], VesilaDuration.allCases)
    func masterSwitchRestoresCombinationAndSelectedDuration(features: MainFeatures, duration: VesilaDuration) throws {
        try withTemporaryDefaults { defaults in
            let preferences = VesilaPreferences(stayActiveWhenLocked: true, duration: duration, lastActiveFeatures: features)
            PreferencesStore(defaults: defaults).save(preferences)
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            let before = Date.now

            controller.setVesilaActive(true)
            #expect(controller.state.activeFeatures == features)
            #expect(controller.state.preferences == preferences)
            if let seconds = duration.seconds {
                let expiration = try #require(controller.state.expirationDate)
                let timer = try #require(controller.expirationTimer)
                #expect(expiration >= before.addingTimeInterval(seconds))
                #expect(expiration <= Date.now.addingTimeInterval(seconds))
                #expect(timer.isValid)
                #expect(abs(timer.fireDate.timeIntervalSince(expiration)) < 1)
            } else {
                #expect(controller.state.expirationDate == nil)
                #expect(controller.expirationTimer == nil)
            }
        }
    }

    @Test func masterSwitchOffClearsSessionAndKeepsPreferences() throws {
        try withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(true)
            controller.selectDuration(.twoHours)
            controller.setVesilaActive(true)
            let preferences = controller.state.preferences
            let timer = try #require(controller.expirationTimer)

            controller.setVesilaActive(false)
            #expect(controller.state.activeFeatures == .none)
            #expect(controller.state.expirationDate == nil)
            #expect(controller.expirationTimer == nil)
            #expect(!timer.isValid)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
            #expect(controller.state.preferences == preferences)
            #expect(PreferencesStore(defaults: defaults).load() == preferences)
            #expect(VesilaFormatter.statusLine(for: controller.state, at: .now) == "Inactive")
        }
    }

    @Test(arguments: [MainFeatures.both, MainFeatures(presence: true, systemAwake: false)])
    func masterSwitchWithoutAccessibilityRestoresWhatItCanAndRendersActualState(features: MainFeatures) {
        withTemporaryDefaults { defaults in
            PreferencesStore(defaults: defaults).save(VesilaPreferences(lastActiveFeatures: features))
            let controller = makeController(defaults: defaults)
            defer { controller.shutdown() }
            var prompts = 0
            var renderedState: VesilaState?
            controller.onAccessibilityRequired = { prompts += 1 }
            controller.onChange = { renderedState = $0 }

            controller.setVesilaActive(true)
            #expect(controller.state.activeFeatures == MainFeatures(presence: false, systemAwake: features.systemAwake))
            #expect(controller.state.isSessionActive == features.systemAwake)
            #expect(prompts == 1)
            #expect(renderedState == controller.state, "the clicked switch reflects the actual session")
            if !features.systemAwake {
                #expect(controller.state.expirationDate == nil)
                #expect(controller.expirationTimer == nil)
                #expect(controller.state.preferences.lastActiveFeatures == features)
            }
        }
    }

    @Test func masterSwitchMatchingStateDoesNothing() {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            var renders = 0
            var prompts = 0
            controller.onChange = { _ in renders += 1 }
            controller.onAccessibilityRequired = { prompts += 1 }
            let inactiveState = controller.state
            controller.setVesilaActive(false)
            #expect(controller.state == inactiveState)
            #expect(renders == 0)

            controller.setVesilaActive(true)
            let activeState = controller.state
            let timer = controller.expirationTimer
            controller.setVesilaActive(true)
            #expect(controller.state == activeState)
            #expect(controller.expirationTimer === timer)
            #expect(renders == 1)
            #expect(prompts == 0)
        }
    }

    @Test func masterSwitchOffCancelsPendingPresenceActivation() {
        withTemporaryDefaults { defaults in
            var granted = false
            let controller = makeController(defaults: defaults, accessibilityGranted: { granted })
            defer { controller.shutdown() }
            controller.setSystemAwakeActive(true)
            controller.activatePresenceWhenAccessibilityGranted()

            controller.setVesilaActive(false)
            granted = true
            RunLoop.main.run(until: .now + 1.5)
            #expect(!controller.state.isSessionActive)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
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

    @Test(arguments: [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification], [true, false])
    func sleepAndUserSwitchTurnEverythingOff(notification: Notification.Name, stayActiveWhenLocked: Bool) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(stayActiveWhenLocked)
            controller.quickToggle()
            #expect(controller.state.isSessionActive)

            NSWorkspace.shared.notificationCenter.post(name: notification, object: nil)
            #expect(controller.state.activeFeatures == .none)
            #expect(controller.state.expirationDate == nil)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess().isEmpty)
        }
    }

    /// The lid can't be closed from a test, so this drives the handler the lid monitor calls.
    @Test(arguments: [true, false])
    func lidCloseTurnsEverythingOff(stayActiveWhenLocked: Bool) {
        withTemporaryDefaults { defaults in
            let controller = makeController(defaults: defaults, accessibilityGranted: { true })
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(stayActiveWhenLocked)
            controller.quickToggle()
            #expect(controller.state.isSessionActive)

            controller.handleInterruption(.lidClosed)
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
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
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

    @Test func aLockWithStayActiveWhenLockedOffAbandonsAPendingPresenceActivation() {
        withTemporaryDefaults { defaults in
            var granted = false
            let controller = makeController(defaults: defaults, accessibilityGranted: { granted })
            defer { controller.shutdown() }

            controller.activatePresenceWhenAccessibilityGranted()
            controller.handleInterruption(.screenLocked)
            granted = true
            RunLoop.main.run(until: .now + 1.5)
            #expect(!controller.state.isSessionActive, "Vesila must stay off after a lock, even if access arrives later")
        }
    }

    /// Stay Active When Locked keeps a running session, not a pending activation: after the lock,
    /// granting Accessibility must not switch Presence on, and the running System Awake session
    /// (features, countdown, timer, assertion) must be exactly as it was.
    @Test func anIgnoredLockKeepsTheSessionButAbandonsAPendingPresenceActivation() throws {
        try withTemporaryDefaults { defaults in
            var granted = false
            let controller = makeController(defaults: defaults, accessibilityGranted: { granted })
            defer { controller.shutdown() }
            controller.setStayActiveWhenLocked(true)
            controller.selectDuration(.thirtyMinutes)
            controller.setSystemAwakeActive(true)
            let beforeLock = controller.state
            let expiration = try #require(controller.state.expirationDate)
            let timer = try #require(controller.expirationTimer)

            controller.activatePresenceWhenAccessibilityGranted()
            var renders = 0
            controller.onChange = { _ in renders += 1 }
            controller.handleInterruption(.screenLocked)
            granted = true
            RunLoop.main.run(until: .now + 1.5)

            // No render means neither the lock nor a late activation ran `update(_:)`.
            #expect(renders == 0)
            #expect(!controller.state.activeFeatures.presence, "the lock abandoned the pending activation")
            #expect(controller.state == beforeLock)
            #expect(controller.state.activeFeatures == MainFeatures(presence: false, systemAwake: true))
            #expect(controller.state.expirationDate == expiration)
            #expect(controller.expirationTimer === timer, "the lock neither cancels nor reschedules it")
            #expect(timer.isValid)
            #expect(vesilaPowerAssertionTypesHeldByThisProcess() == [systemSleepAssertionType])
        }
    }
}

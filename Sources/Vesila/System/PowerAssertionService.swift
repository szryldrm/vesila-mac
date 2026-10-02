import IOKit.pwr_mgt
import OSLog

/// Owns Vesila's IOKit power assertions (visible in `pmset -g assertions`).
///
/// `update` converges on the requested state, so calling it repeatedly never leaks or
/// double-releases an assertion. System Awake prevents both idle system and idle display sleep.
/// If either assertion fails, both are released.
final class PowerAssertionService {
    private var systemSleepAssertion: IOPMAssertionID?
    private var displaySleepAssertion: IOPMAssertionID?

    private let createAssertion: (String, String) -> IOPMAssertionID?
    private let releaseAssertion: (IOPMAssertionID) -> Void

    /// Test hooks exercise partial acquisition failure without depending on powerd failures.
    init(createAssertion: ((String, String) -> IOPMAssertionID?)? = nil,
         releaseAssertion: ((IOPMAssertionID) -> Void)? = nil) {
        self.createAssertion = createAssertion ?? Self.create
        self.releaseAssertion = releaseAssertion ?? Self.releaseID
    }

    /// Returns false when `preventSystemSleep` was requested but either assertion couldn't be created.
    @discardableResult
    func update(preventSystemSleep: Bool) -> Bool {
        if preventSystemSleep {
            acquire(&systemSleepAssertion, type: kIOPMAssertionTypePreventUserIdleSystemSleep, name: "Vesila — System Awake")
            acquire(&displaySleepAssertion, type: kIOPMAssertionTypePreventUserIdleDisplaySleep, name: "Vesila — Display Awake")
            guard systemSleepAssertion != nil && displaySleepAssertion != nil else {
                releaseAll()
                return false
            }
        } else {
            release(&systemSleepAssertion)
            release(&displaySleepAssertion)
        }
        return true
    }

    func releaseAll() {
        update(preventSystemSleep: false)
    }

    deinit {
        releaseAll()
    }

    private func acquire(_ assertion: inout IOPMAssertionID?, type: String, name: String) {
        guard assertion == nil else { return }
        assertion = createAssertion(type, name)
    }

    private func release(_ assertion: inout IOPMAssertionID?) {
        guard let assertionID = assertion else { return }
        assertion = nil
        releaseAssertion(assertionID)
    }

    private static func create(type: String, name: String) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            Logger.vesila.error("Could not create \(type, privacy: .public) assertion (IOReturn \(result))")
            return nil
        }
        return assertionID
    }

    private static func releaseID(_ assertionID: IOPMAssertionID) {
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            Logger.vesila.error("Could not release power assertion \(assertionID) (IOReturn \(result))")
        }
    }
}

import IOKit.pwr_mgt
import OSLog

/// Owns Vesila's IOKit power assertions (visible in `pmset -g assertions`).
///
/// `update` converges on the requested state, so calling it repeatedly never leaks or
/// double-releases an assertion. System Awake is the only assertion Vesila holds; the display is
/// always free to sleep.
final class PowerAssertionService {
    private var systemSleepAssertion: IOPMAssertionID?

    /// Returns false when `preventSystemSleep` was requested but its assertion couldn't be created.
    @discardableResult
    func update(preventSystemSleep: Bool) -> Bool {
        if preventSystemSleep {
            Self.acquire(&systemSleepAssertion, type: kIOPMAssertionTypePreventUserIdleSystemSleep, name: "Vesila — System Awake")
        } else {
            Self.release(&systemSleepAssertion)
        }
        return !preventSystemSleep || systemSleepAssertion != nil
    }

    func releaseAll() {
        update(preventSystemSleep: false)
    }

    deinit {
        releaseAll()
    }

    private static func acquire(_ assertion: inout IOPMAssertionID?, type: String, name: String) {
        guard assertion == nil else { return }
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            Logger.vesila.error("Could not create \(type, privacy: .public) assertion (IOReturn \(result))")
            return
        }
        assertion = assertionID
    }

    private static func release(_ assertion: inout IOPMAssertionID?) {
        guard let assertionID = assertion else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            Logger.vesila.error("Could not release power assertion \(assertionID) (IOReturn \(result))")
        }
        assertion = nil
    }
}

import Foundation
import IOKit.pwr_mgt

/// Runs `body` with a throwaway UserDefaults domain, removed afterwards.
func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "VesilaTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

/// Types of the power assertions this test process currently holds under Vesila's names, as powerd
/// reports them (the same data `pmset -g assertions` shows). One entry per assertion.
func vesilaPowerAssertionTypesHeldByThisProcess() -> [String] {
    var assertionsByProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&assertionsByProcess) == kIOReturnSuccess,
          let byProcess = assertionsByProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    else { return [] }

    let ours = byProcess[NSNumber(value: getpid())] ?? []
    return ours
        .filter { ($0["AssertName"] as? String)?.hasPrefix("Vesila") == true }
        .compactMap { $0["AssertType"] as? String }
        .sorted()
}

let systemSleepAssertionType = "PreventUserIdleSystemSleep"
let displaySleepAssertionType = "PreventUserIdleDisplaySleep"

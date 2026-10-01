import AppKit
import Sparkle

/// Pure configuration gate, also used by tests without starting Sparkle or making requests.
enum UpdateConfiguration {
    static func unavailableReason(bundleURL: URL, info: [String: Any]) -> String? {
        guard bundleURL.pathExtension == "app",
              let version = info["CFBundleShortVersionString"] as? String,
              !version.isEmpty, version != "dev" else {
            return "Automatic updates are available only in a packaged release of Vesila. This is a development run."
        }
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil else {
            return "This build does not have a valid HTTPS update feed configured."
        }
        guard let key = info["SUPublicEDKey"] as? String,
              let decoded = Data(base64Encoded: key), decoded.count == 32 else {
            return "This build does not have an update verification key configured. Install an updater-enabled release to check for updates."
        }
        return nil
    }
}

/// AppDelegate retains this owner for the application's lifetime; Sparkle delegates are weak.
@MainActor
final class UpdaterController: NSObject, SPUStandardUserDriverDelegate {
    private var standardController: SPUStandardUpdaterController?
    private var checkObservation: NSKeyValueObservation?
    private var unavailableReason: String?
    private var didStart = false

    // Keep the fallback button usable so development runs can explain why updates are unavailable.
    @objc dynamic private(set) var canCheckForUpdates = true

    func start() {
        guard !didStart else { return }
        didStart = true
        unavailableReason = UpdateConfiguration.unavailableReason(
            bundleURL: Bundle.main.bundleURL, info: Bundle.main.infoDictionary ?? [:]
        )
        guard unavailableReason == nil else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self
        )
        standardController = controller
        checkObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheckForUpdates = change.newValue ?? false
            // Sparkle's updater and our custom button are main-thread objects.
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = canCheckForUpdates
            }
        }
        controller.startUpdater()
    }

    func checkForUpdates() {
        start()
        if let reason = unavailableReason {
            let alert = NSAlert()
            alert.messageText = "Updates Unavailable"
            alert.informativeText = reason
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        guard canCheckForUpdates else { return }
        standardController?.checkForUpdates(nil)
    }

    // Sparkle's delegate requirements are nonisolated, but its callbacks run on the main thread.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        // Use Sparkle's gentle scheduling policy; bring its alert forward without adding a Dock icon.
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

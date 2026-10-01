import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferencesStore = PreferencesStore()
    private var controller: VesilaController?
    private var statusBarController: StatusBarController?
    private var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already hides the Dock icon in the packaged app; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        let controller = VesilaController(preferencesStore: preferencesStore)
        self.controller = controller
        statusBarController = StatusBarController(controller: controller)

        if !preferencesStore.isOnboardingCompleted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    /// Shown on every launch until the user presses Continue; closing the window doesn't count.
    private func showOnboarding() {
        let onboarding = OnboardingWindowController(preferencesStore: preferencesStore) { [weak self] in
            self?.onboardingWindowController = nil
        }
        onboardingWindowController = onboarding
        onboarding.show()
    }
}

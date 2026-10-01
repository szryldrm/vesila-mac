import AppKit
import ApplicationServices

/// Presence needs Accessibility to post its synthetic mouse-move. Nothing else in Vesila does.
enum AccessibilityPermission {
    /// The value of kAXTrustedCheckOptionPrompt. The imported constant is a mutable global,
    /// which Swift's concurrency checking rejects.
    static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// The one way Vesila asks for access, used by onboarding and by the Presence alert.
    /// Asking with the prompt option is what registers Vesila in the Accessibility list and lets macOS
    /// show its own prompt; opening the pane then takes the user straight to Vesila's switch.
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions([promptOptionKey: true] as CFDictionary)
        openSystemSettings()
    }

    private static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

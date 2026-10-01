import AppKit

/// First-launch window explaining Presence (and its Accessibility requirement) and System Awake.
/// Only Continue marks onboarding as done; Accessibility is optional.
final class OnboardingWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 440, height: 380)
    private static let permissionRefreshInterval: TimeInterval = 1.5

    private let preferencesStore: PreferencesStore
    private let onClose: () -> Void
    private let accessibilityButton = VesilaActionButton(title: "Enable Accessibility", style: .secondary)
    private let continueButton = VesilaActionButton(title: "Continue", style: .primary)
    private var permissionRefreshTimer: Timer?

    init(preferencesStore: PreferencesStore, onClose: @escaping () -> Void) {
        self.preferencesStore = preferencesStore
        self.onClose = onClose

        let window = WindowChrome.makeWindow(size: Self.contentSize, title: "Welcome to Vesila")
        super.init(window: window)
        window.delegate = self

        accessibilityButton.onAction = { [weak self] in self?.enableAccessibilityTapped() }
        continueButton.onAction = { [weak self] in self?.continueTapped() }

        window.contentView = makeContentView()
        updateAccessibilityButtonState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        startPermissionRefresh()
    }

    private func makeContentView() -> NSView {
        let icon = WindowChrome.makeAppIconView()
        let title = WindowChrome.makeAppNameLabel()

        let subtitle = NSTextField(labelWithString: "Stay present. Stay awake.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        let presenceSection = makeSection(
            symbolName: "person.fill.checkmark",
            title: "Presence",
            description: "Keeps your status active while you read, think, or review.",
            note: "Requires Accessibility access."
        )
        let systemAwakeSection = makeSection(
            symbolName: "sun.max.fill",
            title: "System Awake",
            description: "Prevents your Mac from sleeping, and can optionally keep the display awake.",
            note: "No additional permission required."
        )

        let buttonRow = NSStackView(views: [accessibilityButton, continueButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let content = NSStackView(views: [icon, title, subtitle, presenceSection, systemAwakeSection, buttonRow])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 16
        content.setCustomSpacing(8, after: icon)
        content.setCustomSpacing(4, after: title)
        content.setCustomSpacing(16, after: subtitle)
        content.setCustomSpacing(16, after: presenceSection)
        content.setCustomSpacing(24, after: systemAwakeSection)
        NSLayoutConstraint.activate([
            presenceSection.widthAnchor.constraint(equalTo: content.widthAnchor),
            systemAwakeSection.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])

        return WindowChrome.makeContentView(size: Self.contentSize, content: content) { [weak self] in
            self?.window?.close()
        }
    }

    private func makeSection(symbolName: String, title: String, description: String, note: String) -> NSView {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor

        let noteLabel = NSTextField(labelWithString: note)
        noteLabel.font = .systemFont(ofSize: 10)
        noteLabel.textColor = .tertiaryLabelColor

        let textStack = NSStackView(views: [titleLabel, descriptionLabel, noteLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [icon, textStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])

        return row
    }

    private func enableAccessibilityTapped() {
        AccessibilityPermission.requestAccess()
    }

    private func continueTapped() {
        preferencesStore.markOnboardingCompleted()
        window?.close()
    }

    private func updateAccessibilityButtonState() {
        if AccessibilityPermission.isGranted {
            accessibilityButton.configure(title: "Accessibility Enabled", symbolName: "checkmark", style: .success)
            accessibilityButton.isEnabled = false
        } else {
            accessibilityButton.configure(title: "Enable Accessibility", symbolName: nil, style: .secondary)
            accessibilityButton.isEnabled = true
        }
    }

    /// Mirrors the permission while the window is open; macOS posts no notification when it changes.
    private func startPermissionRefresh() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = .scheduledOnMain(interval: Self.permissionRefreshInterval, repeats: true, owner: self) { onboarding in
            onboarding.updateAccessibilityButtonState()
        }
    }
}

extension OnboardingWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        updateAccessibilityButtonState()
    }

    func windowWillClose(_ notification: Notification) {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
        onClose()
    }
}

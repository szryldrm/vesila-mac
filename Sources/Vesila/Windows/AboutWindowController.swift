import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 320, height: 270)

    private let updaterController: UpdaterController
    private var updateObservation: NSKeyValueObservation?

    init(updaterController: UpdaterController) {
        self.updaterController = updaterController
        let window = WindowChrome.makeWindow(size: Self.contentSize, title: "About \(VesilaConfig.appName)")
        super.init(window: window)
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    private func makeContentView() -> NSView {
        let icon = WindowChrome.makeAppIconView()
        let title = WindowChrome.makeAppNameLabel()

        let version = NSTextField(labelWithString: "Version \(VesilaConfig.version)")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let tagline = NSTextField(wrappingLabelWithString: VesilaConfig.tagline)
        tagline.font = .systemFont(ofSize: 12)
        tagline.alignment = .center

        let updateButton = VesilaActionButton(title: "Check for Updates", symbolName: "arrow.clockwise", style: .primary)
        updateButton.onAction = { [weak self] in self?.updaterController.checkForUpdates() }
        updateObservation = updaterController.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak updateButton] _, change in
            let canCheckForUpdates = change.newValue ?? false
            MainActor.assumeIsolated {
                updateButton?.isEnabled = canCheckForUpdates
            }
        }
        let githubButton = VesilaActionButton(title: "GitHub", symbolName: "arrow.up.right", style: .secondary)
        githubButton.onAction = { if let url = VesilaConfig.githubURL { NSWorkspace.shared.open(url) } }
        githubButton.isEnabled = VesilaConfig.githubURL != nil

        let buttonRow = NSStackView(views: [updateButton, githubButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let content = NSStackView(views: [icon, title, version, tagline, buttonRow])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        content.setCustomSpacing(8, after: icon)
        content.setCustomSpacing(4, after: title)
        content.setCustomSpacing(16, after: version)
        content.setCustomSpacing(20, after: tagline)
        tagline.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        return WindowChrome.makeContentView(size: Self.contentSize, content: content) { [weak self] in
            self?.window?.close()
        }
    }

}

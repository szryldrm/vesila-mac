import AppKit

/// Shared look of the About and Onboarding windows: hidden titlebar, full-size content, a small
/// custom close control instead of the traffic lights, and the app icon + name header.
@MainActor
enum WindowChrome {
    private static let appIconSize: CGFloat = 76

    static func makeWindow(size: NSSize, title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        return window
    }

    /// Hosts `content` with the standard margins, and a close control in the top-right corner.
    static func makeContentView(size: NSSize, content: NSStackView, onClose: @escaping () -> Void) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        let closeControl = VesilaCloseControl(action: onClose)
        container.addSubview(closeControl)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
            closeControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            closeControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14)
        ])
        return container
    }

    static func makeAppIconView() -> NSImageView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: appIconSize),
            icon.heightAnchor.constraint(equalToConstant: appIconSize)
        ])
        return icon
    }

    static func makeAppNameLabel() -> NSTextField {
        let label = NSTextField(labelWithString: VesilaConfig.appName)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.alignment = .center
        return label
    }
}

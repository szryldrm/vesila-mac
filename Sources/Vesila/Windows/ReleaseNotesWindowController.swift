import AppKit

@MainActor
final class ReleaseNotesWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 460, height: 470)
    private let version: String
    private let entries: [ReleaseNotes]
    private let onClose: () -> Void

    init(version: String, entries: [ReleaseNotes], onClose: @escaping () -> Void) {
        self.version = version
        self.entries = entries
        self.onClose = onClose
        let window = WindowChrome.makeWindow(size: Self.contentSize, title: "What's New in Vesila \(version)")
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
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
    }

    private func makeContentView() -> NSView {
        let icon = WindowChrome.makeAppIconView()
        let name = WindowChrome.makeAppNameLabel()
        let heading = NSTextField(wrappingLabelWithString: "What's New in Vesila \(version)")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.alignment = .center

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // A width-tracking text container wraps long sentences while the document grows vertically.
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: Self.contentSize.width - 60, height: 220))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: Self.contentSize.width - 68, height: CGFloat.greatestFiniteMagnitude)
        textView.string = entries.map { entry in
            "Version \(entry.version)\n\n" + entry.notes.map { "• \($0)" }.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
        scrollView.documentView = textView

        let continueButton = VesilaActionButton(title: "Continue", style: .primary)
        continueButton.onAction = { [weak self] in self?.window?.close() }
        let content = NSStackView(views: [icon, name, heading, scrollView, continueButton])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 16
        content.setCustomSpacing(8, after: icon)
        content.setCustomSpacing(8, after: name)
        NSLayoutConstraint.activate([
            heading.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 220)
        ])
        return WindowChrome.makeContentView(size: Self.contentSize, content: content) { [weak self] in
            self?.window?.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

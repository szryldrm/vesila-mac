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

        let scrollView = ReleaseNotesScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // The scroll view sizes the document from its actual viewport after Auto Layout.
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
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

/// Keeps the text document as wide as the viewport and as tall as all its wrapped lines.
/// The header and Continue button stay outside this scrolling document.
@MainActor
private final class ReleaseNotesScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        let viewportSize = contentView.bounds.size
        guard viewportSize.width > 0 else { return }
        let inset = textView.textContainerInset
        textContainer.containerSize = NSSize(
            width: max(1, viewportSize.width - 2 * inset.width),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let documentSize = NSSize(
            width: viewportSize.width,
            height: max(viewportSize.height, ceil(layoutManager.usedRect(for: textContainer).maxY) + 2 * inset.height)
        )
        if textView.frame.size != documentSize {
            textView.setFrameSize(documentSize)
        }
    }
}

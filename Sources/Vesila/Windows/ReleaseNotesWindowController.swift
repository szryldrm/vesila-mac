import AppKit

@MainActor
final class ReleaseNotesWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 640, height: 520)
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
        let heading = NSTextField(wrappingLabelWithString: "What's New in Vesila \(version)")
        let title = NSMutableAttributedString(string: "What's New in Vesila ", attributes: [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor.labelColor
        ])
        title.append(NSAttributedString(string: version, attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: NSColor.controlAccentColor
        ]))
        // Attributed text supplies its own paragraph alignment. Apply it to every run,
        // including the highlighted version, so the label always draws as one title.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
        heading.attributedStringValue = title
        heading.alignment = .center
        heading.isEditable = false
        heading.isSelectable = false
        heading.allowsEditingTextAttributes = false

        // Measure at the full card width first: short notes need no scroll view.
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
        textView.string = entries.flatMap(\.notes).map { "• \($0)" }.joined(separator: "\n\n")
        let cardWidth = Self.contentSize.width - 60
        let textWidth = cardWidth - 24
        let textHeight = ReleaseNotesScrollView.sizeDocument(textView, width: textWidth)
        let needsScrolling = textHeight > 220
        let notesView: NSView
        if needsScrolling {
            let scrollView = ReleaseNotesScrollView()
            // Legacy scrollers stay visible even when the system prefers overlay scrollers.
            scrollView.scrollerStyle = .legacy
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = false
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.documentView = textView
            notesView = scrollView
        } else {
            notesView = textView
        }
        notesView.translatesAutoresizingMaskIntoConstraints = false
        let card = ReleaseNotesCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(notesView)
        NSLayoutConstraint.activate([
            notesView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            notesView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            notesView.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            notesView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            notesView.heightAnchor.constraint(equalToConstant: needsScrolling ? 220 : textHeight)
        ])

        let continueButton = VesilaActionButton(title: "Continue", style: .primary)
        continueButton.onAction = { [weak self] in self?.window?.close() }
        var views: [NSView] = [icon, heading, card]
        if needsScrolling {
            let hint = NSTextField(labelWithString: "Scroll to read more ↓")
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .secondaryLabelColor
            views.append(hint)
        }
        let content = NSStackView(views: views)
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 16
        content.setCustomSpacing(8, after: icon)
        if needsScrolling { content.setCustomSpacing(6, after: card) }
        NSLayoutConstraint.activate([
            heading.widthAnchor.constraint(equalTo: content.widthAnchor),
            card.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        let root = WindowChrome.makeContentView(size: Self.contentSize, content: content) { [weak self] in
            self?.window?.close()
        }
        // Keep the primary action at the window bottom, independent of notes length.
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(continueButton)
        NSLayoutConstraint.activate([
            continueButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            continueButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: continueButton.topAnchor, constant: -16)
        ])
        return root
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
        guard let textView = documentView as? NSTextView else { return }

        let viewportSize = contentView.bounds.size
        guard viewportSize.width > 0 else { return }
        Self.sizeDocument(textView, width: viewportSize.width, minimumHeight: viewportSize.height)
    }

    @discardableResult
    static func sizeDocument(_ textView: NSTextView, width: CGFloat, minimumHeight: CGFloat = 0) -> CGFloat {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return minimumHeight }
        let inset = textView.textContainerInset
        textContainer.containerSize = NSSize(
            width: max(1, width - 2 * inset.width),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let height = max(minimumHeight, ceil(layoutManager.usedRect(for: textContainer).maxY) + 2 * inset.height)
        let documentSize = NSSize(width: width, height: height)
        if textView.frame.size != documentSize {
            textView.setFrameSize(documentSize)
        }
        return height
    }
}

/// Semantic AppKit colors resolve for the current Light/Dark appearance when drawn.
@MainActor
private final class ReleaseNotesCardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

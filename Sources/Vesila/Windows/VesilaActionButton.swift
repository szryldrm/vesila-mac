import AppKit

/// Compact pill button shared by the Onboarding and About windows.
final class VesilaActionButton: NSView {
    enum Style {
        case primary
        case secondary
        case success
    }

    static let height: CGFloat = 32
    private static let cornerRadius: CGFloat = 9
    private static let horizontalPadding: CGFloat = 16
    private static let iconLabelGap: CGFloat = 6
    private static let iconDimension: CGFloat = 12

    var onAction: (() -> Void)?

    var isEnabled = true {
        didSet { updateAppearance() }
    }

    private var style: Style
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private lazy var labelLeadingToIcon = label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Self.iconLabelGap)
    private lazy var labelLeadingToEdge = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding)
    private var isHovered = false

    init(title: String, symbolName: String? = nil, style: Style) {
        self.style = style
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconDimension),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconDimension),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        addHoverTrackingArea()
        configure(title: title, symbolName: symbolName, style: style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, symbolName: String?, style: Style) {
        self.style = style
        label.stringValue = title

        if let symbolName {
            let config = NSImage.SymbolConfiguration(pointSize: Self.iconDimension - 1, weight: .semibold)
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconView.isHidden = false
            labelLeadingToEdge.isActive = false
            labelLeadingToIcon.isActive = true
        } else {
            iconView.isHidden = true
            labelLeadingToIcon.isActive = false
            labelLeadingToEdge.isActive = true
        }

        updateAppearance()
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onAction?()
    }

    /// Clicks on the label or icon belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var wantsUpdateLayer: Bool { true }

    /// AppKit calls this with the view's appearance current, and again after Light/Dark changes,
    /// so the layer's CGColors never go stale.
    override func updateLayer() {
        let background: NSColor
        switch style {
        case .primary:
            background = NSColor.controlAccentColor.withAlphaComponent(isHovered ? 0.24 : 0.16)
        case .secondary:
            background = isHovered ? .quaternaryLabelColor : .controlBackgroundColor
        case .success:
            background = NSColor.systemGreen.withAlphaComponent(0.14)
        }
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = style == .secondary ? 1 : 0
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func updateAppearance() {
        let foreground: NSColor
        switch style {
        case .primary: foreground = .controlAccentColor
        case .secondary: foreground = .labelColor
        case .success: foreground = .systemGreen
        }
        label.textColor = foreground
        iconView.contentTintColor = foreground
        alphaValue = (isEnabled || style == .success) ? 1 : 0.55
        needsDisplay = true
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label.stringValue }
    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onAction?()
        return true
    }
}

/// Small subtle close control used in place of the hidden traffic-light buttons.
final class VesilaCloseControl: NSView {
    private let iconView = NSImageView()
    private let action: () -> Void
    private var isHovered = false

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 11

        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(config)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 9),
            iconView.heightAnchor.constraint(equalToConstant: 9)
        ])

        addHoverTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = (isHovered ? NSColor.quaternaryLabelColor : .clear).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Close" }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}

import AppKit

/// A single accessible toggle whose explicitly resolved layer background carries its state.
/// System switch rendering can cache the wrong appearance before menu window attachment;
/// this control resolves its own colors, like MenuSurfaceView, instead of using a bezel.
class StateCardView: MenuSurfaceView {
    enum Layout {
        case prominent
        case compact
    }

    private let cardLayout: Layout
    private let titleLabel: NSTextField
    private let icon = NSImageView()
    private let hoverLayer = CALayer()
    private let onToggle: (Bool) -> Void
    private let requirement: String?
    private var isHovered = false
    private var isPressed = false
    private(set) var isOn = false
    private(set) var isEnabled = true

    init(title: String, symbol: String, layout: Layout = .prominent, requirement: String? = nil,
         onToggle: @escaping (Bool) -> Void) {
        cardLayout = layout
        titleLabel = NSTextField(labelWithString: title)
        self.onToggle = onToggle
        self.requirement = requirement
        super.init()
        let isCompact = layout == .compact
        titleLabel.font = .systemFont(ofSize: isCompact ? 11.5 : 12, weight: .medium)
        titleLabel.maximumNumberOfLines = isCompact ? 1 : 2
        titleLabel.lineBreakMode = isCompact ? .byClipping : .byWordWrapping
        if isCompact {
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        titleLabel.setAccessibilityElement(false)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.setAccessibilityElement(false)
        let content = NSStackView(views: [icon, titleLabel])
        content.orientation = isCompact ? .horizontal : .vertical
        content.alignment = isCompact ? .centerY : .leading
        content.spacing = isCompact ? MenuStyle.smallGap : MenuStyle.childGap
        let iconSize: CGFloat = isCompact ? 14 : 16
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: isCompact ? 38 : 76),
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize)
        ])
        if isCompact {
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuStyle.gap),
                content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -MenuStyle.gap),
                content.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            MenuStyle.pin(content, to: self, inset: MenuStyle.padding)
            titleLabel.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        layer?.addSublayer(hoverLayer)
        addHoverTrackingArea()
        update(isOn: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        guard cardLayout == .compact else { return super.intrinsicContentSize }
        // Reserve the complete label, icon, gap, and both horizontal insets.
        return NSSize(width: titleLabel.intrinsicContentSize.width + 14 + MenuStyle.smallGap + 2 * MenuStyle.gap,
                      height: 38)
    }

    func update(isOn: Bool, isEnabled: Bool = true) {
        self.isOn = isOn && isEnabled
        self.isEnabled = isEnabled
        if !isEnabled { isHovered = false; isPressed = false }
        fillColor = !isEnabled ? CardColor.disabledSurface : (isOn ? CardColor.accentFill : CardColor.surface)
        let tint: NSColor = isEnabled ? .labelColor : .tertiaryLabelColor
        titleLabel.textColor = tint
        icon.contentTintColor = tint
        toolTip = isEnabled ? nil : requirement
        setAccessibilityHelp(toolTip)
        updateLayer()
    }

    override func layout() {
        super.layout()
        hoverLayer.frame = bounds
        updateLayer()
    }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (isOn && isEnabled ? CardColor.accentBorder : NSColor.clear).cgColor
            layer?.borderWidth = isOn && isEnabled ? 1 : 0
            hoverLayer.backgroundColor = CardColor.hover.cgColor
            hoverLayer.opacity = isEnabled && (isHovered || isPressed) ? 1 : 0
        }
    }

    // The card, rather than its decorative descendants, receives pointer input.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        updateLayer()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateLayer()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        window.makeFirstResponder(self)
        isPressed = true
        updateLayer()
        defer { isPressed = false; updateLayer() }
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            isPressed = inside && isEnabled
            updateLayer()
            if next.type == .leftMouseUp {
                if inside { toggle() }
                return
            }
        }
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if [" ", "\r", "\n"].contains(event.charactersIgnoringModifiers ?? "") {
            toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    private func toggle() {
        guard isEnabled else { return }
        update(isOn: !isOn)
        onToggle(isOn)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityLabel() -> String? { titleLabel.stringValue }
    override func accessibilityValue() -> Any? { isOn }
    override func isAccessibilityEnabled() -> Bool { isEnabled }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        toggle()
        return true
    }
}

import AppKit

enum MenuStyle {
    static let width: CGFloat = 296
    static let inset: CGFloat = 10
    static let smallGap: CGFloat = 4
    static let childGap: CGFloat = 6
    static let gap: CGFloat = 8
    static let sectionGap: CGFloat = 10
    static let padding: CGFloat = 12
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8
    static let animationDuration: TimeInterval = 0.16

    @MainActor
    static func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }
}

/// Translucent fills used by the menu. All are dynamic, so they follow Light/Dark Mode and
/// Accent Color changes while the app is running.
enum CardColor {
    static let surface = adaptive(light: 0.07, dark: 0.10, color: .labelColor)
    static let hover = adaptive(light: 0.10, dark: 0.14, color: .labelColor)
    /// Active Presence / System Awake card, and the selected duration pill.
    static let accentFill = adaptive(light: 0.75, dark: 0.75, color: .controlAccentColor)
    /// Active Keep Display Awake row, deliberately weaker than `accentFill`.
    static let accentFillSubtle = adaptive(light: 0.58, dark: 0.58, color: .controlAccentColor)
    /// Selected duration pill outline.
    static let accentBorder = adaptive(light: 0.55, dark: 0.55, color: .controlAccentColor)

    /// Status card tint: neutral when idle, orange for Presence, blue for System Awake, green for both.
    static func statusTint(for features: MainFeatures) -> NSColor? {
        switch (features.presence, features.systemAwake) {
        case (false, false): return nil
        case (true, false): return .systemOrange
        case (false, true): return .systemBlue
        case (true, true): return .systemGreen
        }
    }

    static func statusFill(for features: MainFeatures) -> NSColor {
        guard let tint = statusTint(for: features) else { return surface }
        return adaptive(light: 0.75, dark: 0.75, color: tint)
    }

    /// Resolves `color` at draw time, so dynamic system colors stay live.
    private static func adaptive(light: CGFloat, dark: CGFloat, color: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            color.withAlphaComponent(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }
}

extension NSView {
    /// Mouse enter/exit tracking over the view. `.inVisibleRect` keeps the area in sync with the
    /// view's geometry, so it never has to be rebuilt in `updateTrackingAreas()`.
    func addHoverTrackingArea() {
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
}

/// Rounded translucent card background. Setting `fillColor` animates to it (instantly under Reduce Motion).
class MenuSurfaceView: NSView {
    var fillColor: NSColor = CardColor.surface {
        didSet { animateFill() }
    }

    init(cornerRadius: CGFloat = MenuStyle.cardRadius) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func animateFill() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : MenuStyle.animationDuration
            context.allowsImplicitAnimation = true
            updateLayer()
        }
    }
}

/// Borderless text button used for the duration pills and the footer.
final class MenuActionButton: NSButton {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }
    private let isPill: Bool
    private var isHovered = false

    init(title: String, pill: Bool = false) {
        isPill = pill
        super.init(frame: .zero)
        self.title = title
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: pill ? 11 : 10.5, weight: pill ? .medium : .regular)
        wantsLayer = true
        target = self
        action = #selector(activate)
        addHoverTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func activate() { onClick?() }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isEmphasized = isHovered || isHighlighted
        let fill = isSelected ? CardColor.accentFill : (isEmphasized ? CardColor.hover : (isPill ? CardColor.surface : .clear))
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: MenuStyle.controlRadius, yRadius: MenuStyle.controlRadius)
        fill.setFill()
        path.fill()
        if isSelected {
            CardColor.accentBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
            if isHovered {
                CardColor.hover.setFill()
                path.fill()
            }
        }
        // Only assign on change: setting it marks the button for display again.
        let tint: NSColor = isSelected || isEmphasized ? .labelColor : .secondaryLabelColor
        if contentTintColor != tint {
            contentTintColor = tint
        }
        super.draw(dirtyRect)
    }
}

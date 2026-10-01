import AppKit

/// A lightweight native AppKit toggle that visually matches NSSwitch (small size), used in
/// place of NSSwitch for Vesila's Presence / System Awake / Stay Active When Locked controls.
///
/// Do not replace this with NSSwitch. NSSwitch bakes its tinted rendering against whatever
/// appearance was resolvable at the moment its `state` was set. Because Vesila rebuilds its menu
/// content (and every switch in it) from scratch on each open, a freshly-created NSSwitch has its
/// state set before it has a window — and NSSwitch never re-derives that rendering just because
/// the view later gains a real window, so it can silently render "on" as gray until a user
/// interaction forces a full redraw. Repeated attempts to force NSSwitch to re-resolve its
/// appearance after window attachment did not fix this reliably.
///
/// VesilaToggleControl sidesteps the problem structurally: it draws its own two CALayers
/// (track + thumb) with explicitly resolved CGColors, rather than relying on a system
/// control's private, appearance-caching internal renderer. A plain CALayer background
/// color always reflects whatever it was last set to, independent of window attachment
/// timing, so there is no equivalent "stale until touched" failure mode.
final class VesilaToggleControl: NSControl {
    /// Matches NSSwitch's `.small` controlSize footprint.
    static let size = NSSize(width: 32, height: 18)
    private static let thumbInset: CGFloat = 2
    private static let thumbDiameter: CGFloat = size.height - thumbInset * 2
    private static let animationDuration: TimeInterval = 0.14
    private static let disabledOpacity: Float = 0.38

    var isOn = false {
        didSet {
            guard oldValue != isOn else { return }
            layoutThumb(animated: true)
        }
    }

    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            updateColors()
            updateHoverOverlay()
        }
    }

    private let trackLayer = CALayer()
    private let thumbLayer = CALayer()
    private let hoverLayer = CALayer()
    private var isHovering = false { didSet { updateHoverOverlay() } }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        trackLayer.cornerRadius = Self.size.height / 2
        trackLayer.masksToBounds = true

        hoverLayer.cornerRadius = trackLayer.cornerRadius
        hoverLayer.opacity = 0

        thumbLayer.cornerRadius = Self.thumbDiameter / 2
        thumbLayer.shadowColor = NSColor.black.cgColor
        thumbLayer.shadowOpacity = 0.25
        thumbLayer.shadowRadius = 0.5
        thumbLayer.shadowOffset = CGSize(width: 0, height: -0.5)

        layer?.addSublayer(trackLayer)
        trackLayer.addSublayer(hoverLayer)
        layer?.addSublayer(thumbLayer)

        addHoverTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { Self.size }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        hoverLayer.frame = trackLayer.bounds
        CATransaction.commit()
        layoutThumb(animated: false)
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func layoutThumb(animated: Bool) {
        let y = (bounds.height - Self.thumbDiameter) / 2
        let x = isOn ? bounds.width - Self.thumbDiameter - Self.thumbInset : Self.thumbInset
        let frame = CGRect(x: x, y: y, width: Self.thumbDiameter, height: Self.thumbDiameter)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion && window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.animationDuration
                context.allowsImplicitAnimation = true
                thumbLayer.frame = frame
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            thumbLayer.frame = frame
            CATransaction.commit()
        }
        updateColors()
    }

    /// Resolves NSColor.controlAccentColor (and other dynamic system colors) fresh every
    /// time, rather than caching them, so macOS Accent Color and Light/Dark Mode changes
    /// are always reflected the next time this runs.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            trackLayer.backgroundColor = (isOn ? NSColor.controlAccentColor : NSColor.controlColor).cgColor
            thumbLayer.backgroundColor = NSColor.white.cgColor
            hoverLayer.backgroundColor = CardColor.hover.cgColor
        }
        layer?.opacity = isEnabled ? 1 : Self.disabledOpacity
    }

    private func updateHoverOverlay() {
        let targetOpacity: Float = isHovering && isEnabled ? 1 : 0
        guard hoverLayer.opacity != targetOpacity else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : Self.animationDuration
            context.allowsImplicitAnimation = true
            hoverLayer.opacity = targetOpacity
        }
    }

    private func toggleAndSendAction() {
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        var isInsideBounds = true
        trackLoop: while true {
            guard let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break trackLoop }
            let point = convert(next.locationInWindow, from: nil)
            isInsideBounds = bounds.contains(point)
            if next.type == .leftMouseUp { break trackLoop }
        }
        guard isInsideBounds else { return }
        toggleAndSendAction()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityValue() -> Any? { isOn }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        toggleAndSendAction()
        return true
    }
}

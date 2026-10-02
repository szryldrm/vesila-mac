import AppKit

/// One focusable wall-clock component. AppKit owns first responder and key-view traversal;
/// focus paints the whole segment immediately, independent of field-editor selection.
final class TimeSegmentView: NSControl {
    var onChange: ((Int) -> Void)?
    var onNavigate: ((Bool) -> Void)?
    private(set) var value = 0
    private let maximum: Int
    private var typedDigits = ""
    var isActive: Bool { window?.firstResponder === self }

    init(label: String, maximum: Int) {
        self.maximum = maximum
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(label)
        setAccessibilityHelp("Use Up and Down to change, Left and Right or Tab to move between components")
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 26)
        ])
        update(value: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        typedDigits = ""
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        typedDigits = ""
        needsDisplay = true
        return true
    }

    func update(value: Int) {
        self.value = value
        setAccessibilityValue(String(format: "%02d", value))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: increment(by: 1)
        case 125: increment(by: -1)
        case 123: typedDigits = ""; onNavigate?(false)
        case 124: typedDigits = ""; onNavigate?(true)
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default:
            guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
                  let digits = event.characters, digits.count == 1,
                  digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                super.keyDown(with: event)
                return
            }
            typedDigits += digits
            if typedDigits.count > 2 || (Int(typedDigits) ?? 0) > maximum { typedDigits = digits }
            if let candidate = Int(typedDigits) { onChange?(candidate) }
            if typedDigits.count == 2 { typedDigits = "" }
        }
    }

    func increment(by delta: Int) {
        typedDigits = ""
        onChange?((value + delta + maximum + 1) % (maximum + 1))
    }

    override func accessibilityPerformIncrement() -> Bool { increment(by: 1); return true }
    override func accessibilityPerformDecrement() -> Bool { increment(by: -1); return true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        // An opaque accent and system selected text color provide native selection contrast
        // in both appearances, including graphite and other user-selected accent colors.
        (isActive ? NSColor.selectedContentBackgroundColor : CardColor.surface).setFill()
        path.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isActive ? NSColor.selectedTextColor : NSColor.labelColor
        ]
        let text = String(format: "%02d", value) as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

/// Compact hour : minute pair. Only the focused component carries selection styling.
final class SegmentedTimeView: MenuSurfaceView {
    let hour: TimeSegmentView
    let minute: TimeSegmentView
    var onChange: ((Int) -> Void)?
    private(set) var minutes = 0

    init(label: String) {
        hour = TimeSegmentView(label: "\(label) hour", maximum: 23)
        minute = TimeSegmentView(label: "\(label) minute", maximum: 59)
        super.init(cornerRadius: MenuStyle.controlRadius)
        let colon = NSTextField(labelWithString: ":")
        colon.font = .systemFont(ofSize: 12)
        colon.textColor = .secondaryLabelColor
        colon.setAccessibilityElement(false)
        let row = NSStackView(views: [hour, colon, minute])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 2
        MenuStyle.pin(row, to: self, inset: 3)
        hour.onChange = { [weak self] value in
            guard let self else { return }
            self.onChange?(value * 60 + self.minutes % 60)
        }
        minute.onChange = { [weak self] value in
            guard let self else { return }
            self.onChange?(self.minutes / 60 * 60 + value)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(minutes: Int) {
        self.minutes = minutes
        hour.update(value: minutes / 60)
        minute.update(value: minutes % 60)
    }
}

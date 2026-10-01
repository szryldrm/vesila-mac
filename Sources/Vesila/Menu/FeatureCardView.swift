import AppKit

/// One of the two side-by-side main feature cards (Presence, System Awake).
final class FeatureCardView: MenuSurfaceView {
    private let toggle = VesilaToggleControl()
    private let onToggle: (Bool) -> Void

    init(title: String, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init()
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel(title)
        let switchRow = NSStackView(views: [NSView(), toggle])
        switchRow.orientation = .horizontal
        let content = NSStackView(views: [label, switchRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = MenuStyle.gap
        MenuStyle.pin(content, to: self, inset: MenuStyle.padding)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 76),
            switchRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            switchRow.heightAnchor.constraint(equalTo: toggle.heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggled() { onToggle(toggle.isOn) }

    func update(isOn: Bool) {
        toggle.isOn = isOn
        fillColor = isOn ? CardColor.accentFill : CardColor.surface
    }
}

/// Full-width row for Stay Active When Locked. Always enabled: it's a remembered preference, not
/// part of the session, so it doesn't depend on System Awake or the Active for timer.
final class StayActiveWhenLockedRowView: MenuSurfaceView {
    private static let title = "Stay Active When Locked"

    private let toggle = VesilaToggleControl()
    private let label = NSTextField(labelWithString: StayActiveWhenLockedRowView.title)
    private let icon = NSImageView()
    private let onToggle: (Bool) -> Void

    init(onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(cornerRadius: MenuStyle.controlRadius)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .labelColor
        icon.image = NSImage(systemSymbolName: "lock", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel(Self.title)
        let content = NSStackView(views: [icon, label, NSView(), toggle])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = MenuStyle.childGap
        MenuStyle.pin(content, to: self, inset: MenuStyle.gap)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            icon.widthAnchor.constraint(equalToConstant: 16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggled() { onToggle(toggle.isOn) }

    func update(isOn: Bool) {
        toggle.isOn = isOn
        fillColor = isOn ? CardColor.accentFillSubtle : CardColor.surface
    }
}

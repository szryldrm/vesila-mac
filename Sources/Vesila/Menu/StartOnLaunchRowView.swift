import AppKit

/// Application/system preference row, styled like the existing full-width menu control.
final class StartOnLaunchRowView: MenuSurfaceView {
    private let toggle = VesilaToggleControl()
    private let onToggle: (Bool) -> Void

    init(onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(cornerRadius: MenuStyle.controlRadius)
        let label = NSTextField(labelWithString: "Start on Launch")
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .labelColor
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel("Start on Launch")
        let content = NSStackView(views: [label, NSView(), toggle])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = MenuStyle.childGap
        MenuStyle.pin(content, to: self, inset: MenuStyle.gap)
        heightAnchor.constraint(equalToConstant: 38).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggled() { onToggle(toggle.isOn) }

    func update(status: LoginItemStatus) {
        toggle.isOn = status.isEnabled
        fillColor = status.isEnabled ? CardColor.accentFillSubtle : CardColor.surface
        let help = status == .requiresApproval
            ? "Approval required in System Settings > General > Login Items."
            : "Launch Vesila automatically when you sign in to macOS."
        toolTip = help
        toggle.setAccessibilityHelp(help)
    }
}

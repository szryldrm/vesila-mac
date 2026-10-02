import AppKit

/// Activation mode pills, with the existing durations or a compact schedule summary.
final class ActivationView: NSView {
    private var pills: [VesilaActivationMode: MenuActionButton] = [:]
    private let durations: ActiveForView
    private let scheduledContent: NSStackView
    private let summary = NSTextField(labelWithString: "")

    init(onMode: @escaping (VesilaActivationMode) -> Void,
         onDuration: @escaping (VesilaDuration) -> Void, onEdit: @escaping () -> Void) {
        durations = ActiveForView(onSelect: onDuration)
        let edit = MenuActionButton(title: "Edit Schedule…")
        edit.setAccessibilityLabel("Edit Schedule")
        edit.onClick = onEdit
        scheduledContent = NSStackView(views: [summary, edit])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Activation")
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        let modes = NSStackView()
        modes.orientation = .horizontal
        modes.distribution = .fillEqually
        modes.spacing = MenuStyle.smallGap
        for mode in VesilaActivationMode.allCases {
            let pill = MenuActionButton(title: mode.title, pill: true)
            pill.setAccessibilityLabel("\(mode.title) activation")
            pill.onClick = { onMode(mode) }
            modes.addArrangedSubview(pill)
            pill.heightAnchor.constraint(equalTo: modes.heightAnchor).isActive = true
            pills[mode] = pill
        }
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        scheduledContent.orientation = .vertical
        scheduledContent.alignment = .leading
        scheduledContent.spacing = MenuStyle.smallGap
        let content = NSStackView(views: [label, modes, durations, scheduledContent])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = MenuStyle.childGap
        MenuStyle.pin(content, to: self)
        NSLayoutConstraint.activate([
            modes.widthAnchor.constraint(equalTo: content.widthAnchor),
            modes.heightAnchor.constraint(equalToConstant: 24),
            durations.widthAnchor.constraint(equalTo: content.widthAnchor),
            scheduledContent.widthAnchor.constraint(equalTo: content.widthAnchor),
            edit.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(preferences: VesilaPreferences) {
        for (mode, pill) in pills {
            pill.isSelected = mode == preferences.activationMode
            pill.setAccessibilityValue(pill.isSelected ? "Selected" : "Not selected")
        }
        durations.update(selected: preferences.duration)
        durations.isHidden = preferences.activationMode != .manual
        scheduledContent.isHidden = preferences.activationMode != .scheduled
        summary.stringValue = VesilaFormatter.scheduleSummary(preferences.schedule)
        summary.setAccessibilityLabel("Schedule")
        summary.setAccessibilityValue(summary.stringValue)
    }
}

import AppKit

/// Activation mode pills, with the existing durations or inline schedule controls.
final class ActivationView: NSView {
    private var pills: [VesilaActivationMode: MenuActionButton] = [:]
    private let durations: ActiveForView
    private let scheduledContent: ScheduleControlsView

    init(onMode: @escaping (VesilaActivationMode) -> Void,
         onDuration: @escaping (VesilaDuration) -> Void,
         onSchedule: @escaping (VesilaSchedule) -> Void) {
        durations = ActiveForView(onSelect: onDuration)
        scheduledContent = ScheduleControlsView(onChange: onSchedule)
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
        let content = NSStackView(views: [label, modes, durations, scheduledContent])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = MenuStyle.childGap
        MenuStyle.pin(content, to: self)
        NSLayoutConstraint.activate([
            modes.widthAnchor.constraint(equalTo: content.widthAnchor),
            modes.heightAnchor.constraint(equalToConstant: 24),
            durations.widthAnchor.constraint(equalTo: content.widthAnchor),
            scheduledContent.widthAnchor.constraint(equalTo: content.widthAnchor)
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
        scheduledContent.update(schedule: preferences.schedule)
    }
}

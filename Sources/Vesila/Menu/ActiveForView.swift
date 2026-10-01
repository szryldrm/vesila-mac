import AppKit

/// "Active for" duration pills. Selecting one leaves the menu open.
final class ActiveForView: NSView {
    private var pills: [VesilaDuration: MenuActionButton] = [:]

    init(onSelect: @escaping (VesilaDuration) -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Active for")
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        let options = NSStackView()
        options.orientation = .horizontal
        options.distribution = .fillEqually
        options.spacing = MenuStyle.smallGap
        for duration in VesilaDuration.allCases {
            let pill = MenuActionButton(title: duration.shortTitle, pill: true)
            pill.toolTip = duration.title
            pill.setAccessibilityLabel(duration.title)
            pill.onClick = { onSelect(duration) }
            options.addArrangedSubview(pill)
            pill.heightAnchor.constraint(equalTo: options.heightAnchor).isActive = true
            pills[duration] = pill
        }
        let content = NSStackView(views: [label, options])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = MenuStyle.childGap
        MenuStyle.pin(content, to: self)
        NSLayoutConstraint.activate([
            options.widthAnchor.constraint(equalTo: content.widthAnchor),
            options.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selected: VesilaDuration) {
        for (duration, pill) in pills {
            pill.isSelected = duration == selected
            pill.setAccessibilityValue(duration == selected ? "Selected" : "Not selected")
        }
    }
}

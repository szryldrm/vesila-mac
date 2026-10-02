import AppKit

/// Login item status and help remain owned by LoginItemController.
final class StartOnLaunchRowView: StateCardView {
    init(onToggle: @escaping (Bool) -> Void) {
        super.init(title: "Start on Launch", symbol: "power", height: 66, onToggle: onToggle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(status: LoginItemStatus) {
        update(isOn: status.isEnabled)
        let help = status == .requiresApproval
            ? "Approval required in System Settings > General > Login Items."
            : "Launch Vesila automatically when you sign in to macOS."
        toolTip = help
        setAccessibilityHelp(help)
    }
}

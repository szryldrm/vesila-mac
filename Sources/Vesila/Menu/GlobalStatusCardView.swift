import AppKit

/// Top card: app name plus one shared status line, tinted by which main features are on.
final class GlobalStatusCardView: MenuSurfaceView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: VesilaConfig.appName)
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        super.init()
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)

        let labels = NSStackView(views: [titleLabel, statusLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = MenuStyle.smallGap
        labels.setHuggingPriority(.required, for: .vertical)
        let content = NSStackView(views: [iconView, labels, NSView()])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = MenuStyle.padding
        MenuStyle.pin(content, to: self, inset: MenuStyle.padding)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 72),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(features: MainFeatures, statusLine: String) {
        fillColor = CardColor.statusFill(for: features)
        iconView.image = VesilaIconLibrary.statusImage(for: features)
        iconView.contentTintColor = CardColor.statusTint(for: features) ?? .secondaryLabelColor
        setStatusLine(statusLine)
    }

    func setStatusLine(_ text: String) {
        statusLabel.stringValue = text
    }
}

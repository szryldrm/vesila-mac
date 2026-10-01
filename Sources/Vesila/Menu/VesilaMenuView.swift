import AppKit

/// The menu's content, hosted as the view of a single NSMenuItem. It is rebuilt each time the
/// menu opens and re-rendered from `VesilaState` on every change while open. It reports user input
/// as `Action`s and never changes state itself.
final class VesilaMenuView: NSView {
    enum Action {
        case setPresence(Bool)
        case setSystemAwake(Bool)
        case setStayActiveWhenLocked(Bool)
        case selectDuration(VesilaDuration)
        case setStartOnLaunch(Bool)
        case showAbout
        case quit
    }

    private let statusCard = GlobalStatusCardView()
    private let presenceCard: FeatureCardView
    private let systemAwakeCard: FeatureCardView
    private let stayActiveRow: StayActiveWhenLockedRowView
    private let durationPicker: ActiveForView
    private let startOnLaunchRow: StartOnLaunchRowView
    private let content = NSStackView()

    init(state: VesilaState, now: Date, loginItemStatus: LoginItemStatus, onAction: @escaping (Action) -> Void) {
        presenceCard = FeatureCardView(title: "Presence") { onAction(.setPresence($0)) }
        systemAwakeCard = FeatureCardView(title: "System Awake") { onAction(.setSystemAwake($0)) }
        stayActiveRow = StayActiveWhenLockedRowView { onAction(.setStayActiveWhenLocked($0)) }
        durationPicker = ActiveForView { onAction(.selectDuration($0)) }
        startOnLaunchRow = StartOnLaunchRowView { onAction(.setStartOnLaunch($0)) }
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: 1))

        let features = NSStackView(views: [presenceCard, systemAwakeCard])
        features.orientation = .horizontal
        features.distribution = .fillEqually
        features.spacing = MenuStyle.childGap
        let separator = NSBox()
        separator.boxType = .separator
        let footer = FooterView(onAbout: { onAction(.showAbout) }, onQuit: { onAction(.quit) })

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = MenuStyle.gap
        for view in [statusCard, features, stayActiveRow, durationPicker, startOnLaunchRow, separator, footer] {
            content.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        content.setCustomSpacing(MenuStyle.childGap, after: features)
        content.setCustomSpacing(MenuStyle.sectionGap, after: stayActiveRow)
        content.setCustomSpacing(MenuStyle.sectionGap, after: startOnLaunchRow)
        content.setCustomSpacing(MenuStyle.smallGap, after: separator)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: MenuStyle.smallGap),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuStyle.inset),
            content.widthAnchor.constraint(equalToConstant: MenuStyle.width - 2 * MenuStyle.inset)
        ])

        startOnLaunchRow.update(status: loginItemStatus)
        render(state, now: now)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(_ state: VesilaState, now: Date) {
        statusCard.update(features: state.activeFeatures, statusLine: VesilaFormatter.statusLine(for: state, at: now))
        presenceCard.update(isOn: state.activeFeatures.presence)
        systemAwakeCard.update(isOn: state.activeFeatures.systemAwake)
        stayActiveRow.update(
            isOn: state.preferences.stayActiveWhenLocked,
            isAvailable: state.isStayActiveWhenLockedAvailable
        )
        durationPicker.update(selected: state.preferences.duration)
        resizeToFitContent()
    }

    func renderLoginItemStatus(_ status: LoginItemStatus) {
        startOnLaunchRow.update(status: status)
    }

    /// Cheap per-second update while the menu is open: only the countdown text changes.
    func refreshCountdown(_ state: VesilaState, now: Date) {
        guard state.remainingTime(at: now) != nil else { return }
        statusCard.setStatusLine(VesilaFormatter.statusLine(for: state, at: now))
    }

    private func resizeToFitContent() {
        layoutSubtreeIfNeeded()
        let size = NSSize(width: MenuStyle.width, height: ceil(content.fittingSize.height) + MenuStyle.smallGap * 2)
        if frame.size != size {
            setFrameSize(size)
            layoutSubtreeIfNeeded()
        }
        // Lets an open menu pick up a changed item height.
        enclosingMenuItem?.menu?.update()
    }
}

final class FooterView: NSView {
    init(onAbout: @escaping () -> Void, onQuit: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let about = MenuActionButton(title: "About Vesila")
        about.onClick = onAbout
        let quit = MenuActionButton(title: "Quit Vesila   ⌘Q")
        quit.setAccessibilityLabel("Quit Vesila")
        quit.onClick = onQuit
        let content = NSStackView(views: [about, NSView(), quit])
        content.orientation = .horizontal
        content.alignment = .centerY
        MenuStyle.pin(content, to: self)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            about.widthAnchor.constraint(equalToConstant: 77),
            quit.widthAnchor.constraint(equalToConstant: 101),
            about.heightAnchor.constraint(equalTo: heightAnchor),
            quit.heightAnchor.constraint(equalTo: heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

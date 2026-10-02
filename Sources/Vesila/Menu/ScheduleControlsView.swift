import AppKit

/// Inline schedule input. Only valid same-day changes reach the controller and persistence.
final class ScheduleControlsView: NSView {
    private let onChange: (VesilaSchedule) -> Void
    private var schedule = VesilaSchedule()
    private var dayPills: [Int: MenuActionButton] = [:]
    private let startTime = SegmentedTimeView(label: "Start time")
    private let endTime = SegmentedTimeView(label: "End time")

    init(calendar: Calendar = .current, onChange: @escaping (VesilaSchedule) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let days = NSStackView()
        days.orientation = .horizontal
        days.distribution = .fillEqually
        days.spacing = MenuStyle.smallGap
        for day in VesilaSchedule.orderedWeekdays(calendar: calendar) {
            let pill = MenuActionButton(title: calendar.veryShortWeekdaySymbols[day - 1], pill: true)
            pill.setAccessibilityLabel(calendar.weekdaySymbols[day - 1])
            pill.onClick = { [weak self] in
                guard let self else { return }
                var updated = self.schedule
                if updated.days.contains(day) { updated.days.remove(day) } else { updated.days.insert(day) }
                self.commit(updated)
            }
            dayPills[day] = pill
            days.addArrangedSubview(pill)
            pill.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        startTime.onChange = { [weak self] minutes in
            guard let self else { return }
            var updated = self.schedule
            updated.startMinute = minutes
            self.commit(updated)
        }
        endTime.onChange = { [weak self] minutes in
            guard let self else { return }
            var updated = self.schedule
            updated.endMinute = minutes
            self.commit(updated)
        }
        let segments = [startTime.hour, startTime.minute, endTime.hour, endTime.minute]
        for (index, segment) in segments.enumerated() {
            if index + 1 < segments.count { segment.nextKeyView = segments[index + 1] }
            let previous = index > 0 ? segments[index - 1] : nil
            let next = index + 1 < segments.count ? segments[index + 1] : nil
            segment.onNavigate = { [weak self, weak previous, weak next] forward in
                guard let destination = forward ? next : previous else { return }
                self?.window?.makeFirstResponder(destination)
            }
        }
        let arrow = NSTextField(labelWithString: "→")
        arrow.font = .systemFont(ofSize: 11)
        arrow.textColor = .tertiaryLabelColor
        arrow.setAccessibilityElement(false)
        let times = NSStackView(views: [startTime, arrow, endTime])
        times.orientation = .horizontal
        times.alignment = .centerY
        times.spacing = MenuStyle.smallGap
        let timeRow = NSView()
        timeRow.translatesAutoresizingMaskIntoConstraints = false
        timeRow.addSubview(times)
        times.translatesAutoresizingMaskIntoConstraints = false
        let content = NSStackView(views: [days, timeRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = MenuStyle.childGap
        MenuStyle.pin(content, to: self)
        NSLayoutConstraint.activate([
            days.widthAnchor.constraint(equalTo: content.widthAnchor),
            timeRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            times.centerXAnchor.constraint(equalTo: timeRow.centerXAnchor),
            times.topAnchor.constraint(equalTo: timeRow.topAnchor),
            times.bottomAnchor.constraint(equalTo: timeRow.bottomAnchor),
            times.leadingAnchor.constraint(greaterThanOrEqualTo: timeRow.leadingAnchor),
            times.trailingAnchor.constraint(lessThanOrEqualTo: timeRow.trailingAnchor)
        ])
        update(schedule: schedule)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(schedule: VesilaSchedule) {
        self.schedule = schedule
        for (day, pill) in dayPills {
            pill.isSelected = schedule.days.contains(day)
            pill.isEnabled = !pill.isSelected || schedule.days.count > 1
            pill.setAccessibilityValue(pill.isSelected ? "Selected" : "Not selected")
            pill.setAccessibilityHelp(pill.isEnabled ? "Toggle schedule day" : "At least one day must remain selected")
        }
        startTime.update(minutes: schedule.startMinute)
        endTime.update(minutes: schedule.endMinute)
    }

    private func commit(_ updated: VesilaSchedule) {
        guard updated.isValid else {
            update(schedule: schedule)
            return
        }
        guard updated != schedule else { return }
        update(schedule: updated)
        onChange(updated)
    }
}

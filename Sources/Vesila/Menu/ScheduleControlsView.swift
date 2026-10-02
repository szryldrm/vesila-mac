import AppKit

/// Inline schedule input. Only valid same-day changes reach the controller and persistence.
final class ScheduleControlsView: NSView {
    private let calendar: Calendar
    private let onChange: (VesilaSchedule) -> Void
    private var schedule = VesilaSchedule()
    private var dayPills: [Int: MenuActionButton] = [:]
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    // A fixed non-transition day keeps these controls editing wall-clock minutes only.
    private var referenceDay: Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
    }

    init(calendar: Calendar = .current, onChange: @escaping (VesilaSchedule) -> Void) {
        self.calendar = calendar
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
        for (picker, label) in [(startPicker, "Start time"), (endPicker, "End time")] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.calendar = calendar
            picker.timeZone = calendar.timeZone
            picker.font = .systemFont(ofSize: 11)
            picker.target = self
            picker.action = #selector(timeChanged)
            picker.setAccessibilityLabel(label)
            picker.translatesAutoresizingMaskIntoConstraints = false
        }
        let startLabel = NSTextField(labelWithString: "Start")
        let endLabel = NSTextField(labelWithString: "End")
        for label in [startLabel, endLabel] {
            label.font = .systemFont(ofSize: 10.5)
            label.textColor = .secondaryLabelColor
        }
        let times = NSStackView(views: [startLabel, startPicker, NSView(), endLabel, endPicker])
        times.orientation = .horizontal
        times.alignment = .centerY
        times.spacing = MenuStyle.smallGap
        let content = NSStackView(views: [days, times])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = MenuStyle.childGap
        MenuStyle.pin(content, to: self)
        NSLayoutConstraint.activate([
            days.widthAnchor.constraint(equalTo: content.widthAnchor),
            times.widthAnchor.constraint(equalTo: content.widthAnchor)
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
        // Clear old bounds before applying new values, so external schedule edits aren't clamped.
        for picker in [startPicker, endPicker] {
            picker.minDate = nil
            picker.maxDate = nil
        }
        startPicker.dateValue = date(for: schedule.startMinute)
        endPicker.dateValue = date(for: schedule.endMinute)
        startPicker.minDate = date(for: 0)
        startPicker.maxDate = date(for: schedule.endMinute - 1)
        endPicker.minDate = date(for: schedule.startMinute + 1)
        endPicker.maxDate = date(for: 1439)
    }

    private func date(for minute: Int) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: referenceDay)!
    }

    @objc private func timeChanged() {
        var updated = schedule
        let start = calendar.dateComponents([.hour, .minute], from: startPicker.dateValue)
        let end = calendar.dateComponents([.hour, .minute], from: endPicker.dateValue)
        updated.startMinute = (start.hour ?? 0) * 60 + (start.minute ?? 0)
        updated.endMinute = (end.hour ?? 0) * 60 + (end.minute ?? 0)
        commit(updated)
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

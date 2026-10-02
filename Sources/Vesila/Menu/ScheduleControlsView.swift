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
            picker.controlSize = .small
            picker.font = .systemFont(ofSize: 11)
            // Let AppKit paint the native field and selected segment against an opaque,
            // appearance-aware background. Suppressing its background can weaken selection
            // contrast in a menu. The surround retains the rounded field geometry.
            picker.isBezeled = false
            picker.isBordered = false
            picker.drawsBackground = true
            picker.backgroundColor = .textBackgroundColor
            picker.textColor = .textColor
            picker.focusRingType = .default
            picker.presentsCalendarOverlay = false
            picker.setContentHuggingPriority(.required, for: .horizontal)
            picker.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        let arrow = NSTextField(labelWithString: "→")
        arrow.font = .systemFont(ofSize: 11)
        arrow.textColor = .tertiaryLabelColor
        arrow.setAccessibilityElement(false)
        let times = NSStackView(views: [startLabel, roundedField(startPicker), arrow, endLabel, roundedField(endPicker)])
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
        synchronize(startPicker, minute: schedule.startMinute, minimum: 0, maximum: schedule.endMinute - 1)
        synchronize(endPicker, minute: schedule.endMinute, minimum: schedule.startMinute + 1, maximum: 1439)
    }

    private func roundedField(_ picker: NSDatePicker) -> NSView {
        let field = MenuSurfaceView(cornerRadius: MenuStyle.controlRadius)
        field.fillColor = .textBackgroundColor
        // Do not clip AppKit's focus ring or selected component drawing.
        field.layer?.masksToBounds = false
        MenuStyle.pin(picker, to: field, inset: MenuStyle.smallGap)
        return field
    }

    private func synchronize(_ picker: NSDatePicker, minute: Int, minimum: Int, maximum: Int) {
        let value = date(for: minute)
        // A native edit already has the right value. Assigning it again during render
        // can reset the selected hour/minute, including on the controller's echo render.
        if picker.dateValue != value {
            picker.minDate = nil
            picker.maxDate = nil
            picker.dateValue = value
        }
        let minDate = date(for: minimum)
        let maxDate = date(for: maximum)
        if picker.minDate != minDate { picker.minDate = minDate }
        if picker.maxDate != maxDate { picker.maxDate = maxDate }
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

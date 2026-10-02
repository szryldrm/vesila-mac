import AppKit

/// A separate editor keeps date-picker input outside NSMenu tracking. Cancel discards the draft.
@MainActor
final class ScheduleWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 400, height: 260)
    private let onSave: (VesilaSchedule) -> Void
    private let calendar: Calendar
    private var days: Set<Int> = []
    private var dayPills: [Int: MenuActionButton] = [:]
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let hint = NSTextField(labelWithString: "")
    private let saveButton = VesilaActionButton(title: "Save", style: .primary)

    init(calendar: Calendar = .current, onSave: @escaping (VesilaSchedule) -> Void) {
        self.calendar = calendar
        self.onSave = onSave
        super.init(window: WindowChrome.makeWindow(size: Self.contentSize, title: "Edit Schedule"))
        window?.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(schedule: VesilaSchedule) {
        days = schedule.days
        let day = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        startPicker.dateValue = calendar.date(bySettingHour: schedule.startMinute / 60, minute: schedule.startMinute % 60, second: 0, of: day)!
        endPicker.dateValue = calendar.date(bySettingHour: schedule.endMinute / 60, minute: schedule.endMinute % 60, second: 0, of: day)!
        validate()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    private var draft: VesilaSchedule {
        let start = calendar.dateComponents([.hour, .minute], from: startPicker.dateValue)
        let end = calendar.dateComponents([.hour, .minute], from: endPicker.dateValue)
        return VesilaSchedule(days: days, startMinute: (start.hour ?? 0) * 60 + (start.minute ?? 0),
                              endMinute: (end.hour ?? 0) * 60 + (end.minute ?? 0))
    }

    private func makeContentView() -> NSView {
        let title = NSTextField(labelWithString: "Edit Schedule")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let dayRow = NSStackView()
        dayRow.orientation = .horizontal
        dayRow.distribution = .fillEqually
        dayRow.spacing = 4
        for day in VesilaSchedule.orderedWeekdays(calendar: calendar) {
            let pill = MenuActionButton(title: calendar.shortWeekdaySymbols[day - 1], pill: true)
            pill.setAccessibilityLabel(calendar.weekdaySymbols[day - 1])
            pill.onClick = { [weak self] in
                guard let self else { return }
                if self.days.contains(day) { self.days.remove(day) } else { self.days.insert(day) }
                self.validate()
            }
            dayPills[day] = pill
            dayRow.addArrangedSubview(pill)
            pill.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        for (picker, label) in [(startPicker, "Start time"), (endPicker, "End time")] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.calendar = calendar
            picker.timeZone = calendar.timeZone
            picker.target = self
            picker.action = #selector(timeChanged)
            picker.setAccessibilityLabel(label)
        }
        let timeRow = NSStackView(views: [NSTextField(labelWithString: "Start"), startPicker,
                                        NSTextField(labelWithString: "End"), endPicker])
        timeRow.orientation = .horizontal
        timeRow.spacing = 10
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let cancel = VesilaActionButton(title: "Cancel", style: .secondary)
        cancel.onAction = { [weak self] in self?.window?.close() }
        saveButton.onAction = { [weak self] in
            guard let self, self.draft.isValid else { return }
            self.onSave(self.draft)
            self.window?.close()
        }
        let buttons = NSStackView(views: [cancel, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let content = NSStackView(views: [title, dayRow, timeRow, hint, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        dayRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return WindowChrome.makeContentView(size: Self.contentSize, content: content) { [weak self] in
            self?.window?.close()
        }
    }

    @objc private func timeChanged() { validate() }

    private func validate() {
        for (day, pill) in dayPills {
            pill.isSelected = days.contains(day)
            pill.setAccessibilityValue(pill.isSelected ? "Selected" : "Not selected")
        }
        saveButton.isEnabled = draft.isValid
        hint.stringValue = days.isEmpty ? "Select at least one day." :
            (draft.endMinute <= draft.startMinute ? "End time must be after start time." : "")
        hint.setAccessibilityValue(hint.stringValue)
    }
}

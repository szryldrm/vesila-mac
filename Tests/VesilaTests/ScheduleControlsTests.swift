import AppKit
import Testing
@testable import Vesila

@Suite("Inline schedule controls")
@MainActor
struct ScheduleControlsTests {
    @Test func daysCommitImmediatelyAndLastDayCannotBeRemoved() throws {
        var changes: [VesilaSchedule] = []
        let controls = ScheduleControlsView(calendar: scheduleCalendar) { changes.append($0) }
        let pills = descendants(of: controls).compactMap { $0 as? MenuActionButton }
        #expect(pills.map(\.title) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(pills.map { $0.accessibilityLabel() } == ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
        controls.update(schedule: VesilaSchedule(days: [2, 3]))
        pills[1].onClick?()
        #expect(changes == [VesilaSchedule(days: [2])])
        #expect(!pills[0].isEnabled)
        pills[0].onClick?()
        #expect(changes.count == 1)
        pills[5].onClick?()
        #expect(changes.last == VesilaSchedule(days: [2, 7]))
        #expect(pills[0].isEnabled)
        #expect(pills[5].isSelected)
    }

    @Test func timeChangesCommitAndInvalidInputRestoresPersistedValues() throws {
        var changes: [VesilaSchedule] = []
        let controls = ScheduleControlsView(calendar: scheduleCalendar) { changes.append($0) }
        let pickers = descendants(of: controls).compactMap { $0 as? NSDatePicker }
        let start = try #require(pickers.first { $0.accessibilityLabel() == "Start time" })
        let end = try #require(pickers.first { $0.accessibilityLabel() == "End time" })
        start.dateValue = start.dateValue.addingTimeInterval(3600)
        _ = start.sendAction(start.action, to: start.target)
        #expect(changes == [VesilaSchedule(startMinute: 600)])
        #expect(end.minDate == start.dateValue.addingTimeInterval(60))
        // Bypass the picker bounds to exercise defensive validation of a same-time edit.
        end.minDate = nil
        end.dateValue = start.dateValue
        _ = end.sendAction(end.action, to: end.target)
        #expect(changes.count == 1)
        #expect(scheduleCalendar.component(.hour, from: end.dateValue) == 18)
        controls.update(schedule: VesilaSchedule(startMinute: 120, endMinute: 240))
        #expect(scheduleCalendar.component(.hour, from: start.dateValue) == 2)
        #expect(scheduleCalendar.component(.hour, from: end.dateValue) == 4)
    }

    @Test func menuExpandsOnlyInScheduledModeAndRoutesEditsWithoutAWindow() throws {
        _ = NSApplication.shared
        var preferences = VesilaPreferences()
        var state = VesilaState(preferences: preferences)
        var actions: [VesilaMenuView.Action] = []
        let menu = VesilaMenuView(state: state, now: scheduleDate(hour: 8), loginItemStatus: .notRegistered) { actions.append($0) }
        let manualHeight = menu.frame.height
        let controls = try #require(descendants(of: menu).compactMap { $0 as? ScheduleControlsView }.first)
        #expect(controls.isHidden)
        preferences.activationMode = .scheduled
        state = VesilaState(preferences: preferences)
        menu.render(state, now: scheduleDate(hour: 8))
        #expect(!controls.isHidden)
        #expect(menu.frame.height > manualHeight)
        let pills = descendants(of: controls).compactMap { $0 as? MenuActionButton }
        pills[5].onClick?()
        let action = try #require(actions.last)
        if case .setSchedule(let schedule) = action {
            #expect(schedule.days == [2, 3, 4, 5, 6, 7])
        } else {
            Issue.record("Inline edit must route directly to setSchedule")
        }
        menu.layoutSubtreeIfNeeded()
        for view in descendants(of: controls) where view is NSDatePicker || view is MenuActionButton {
            #expect(menu.bounds.contains(view.convert(view.bounds, to: menu)))
        }
        #expect(!descendants(of: menu).compactMap { $0 as? NSButton }.contains { $0.title == "Edit Schedule…" })
        preferences.activationMode = .manual
        state = VesilaState(preferences: preferences)
        menu.render(state, now: scheduleDate(hour: 8))
        #expect(controls.isHidden)
        #expect(menu.frame.height == manualHeight)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

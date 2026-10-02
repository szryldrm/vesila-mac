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
        let editors = descendants(of: controls).compactMap { $0 as? SegmentedTimeView }
        let start = try #require(editors.first)
        let end = try #require(editors.last)
        start.hour.increment(by: 1)
        #expect(changes == [VesilaSchedule(startMinute: 600)])
        end.onChange?(600)
        #expect(changes.count == 1)
        #expect(end.minutes == 1080)
        controls.update(schedule: VesilaSchedule(startMinute: 120, endMinute: 240))
        #expect(start.hour.value == 2)
        #expect(end.hour.value == 4)
        #expect(start.hour.accessibilityLabel() == "Start time hour")
        #expect(end.minute.accessibilityLabel() == "End time minute")
    }

    @Test func componentFocusNavigationAndKeyboardEditing() throws {
        _ = NSApplication.shared
        let controls = ScheduleControlsView(calendar: scheduleCalendar) { _ in }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 276, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = controls
        let segments = descendants(of: controls).compactMap { $0 as? TimeSegmentView }
        #expect(segments.count == 4)
        #expect(window.makeFirstResponder(segments[0]))
        #expect(segments.map(\.isActive) == [true, false, false, false])
        func key(_ code: UInt16, characters: String = "", flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        segments[0].keyDown(with: try key(124))
        #expect(segments.map(\.isActive) == [false, true, false, false])
        segments[1].keyDown(with: try key(126))
        #expect(segments[1].value == 1)
        segments[1].keyDown(with: try key(48))
        #expect(segments[2].isActive)
        segments[2].keyDown(with: try key(48, flags: .shift))
        #expect(segments[1].isActive)
        segments[1].keyDown(with: try key(0, characters: "2"))
        segments[1].keyDown(with: try key(0, characters: "5"))
        #expect(segments[1].value == 25)
        segments[1].onNavigate?(false)
        #expect(segments[0].isActive)
        // Component wrapping never rolls the adjacent component or produces invalid hours.
        controls.update(schedule: VesilaSchedule(startMinute: 0, endMinute: 1439))
        segments[3].increment(by: 1)
        #expect(segments[2].value == 23)
        #expect(segments[3].value == 0)
        controls.update(schedule: VesilaSchedule(startMinute: 0, endMinute: 60))
        segments[0].increment(by: -1)
        #expect(segments[0].value == 0) // Invalid range rejected.
        window.makeFirstResponder(nil)
        #expect(!segments.contains { $0.isActive })
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
        for view in descendants(of: controls) where view is TimeSegmentView || view is MenuActionButton {
            #expect(menu.bounds.contains(view.convert(view.bounds, to: menu)))
        }
        #expect(!descendants(of: controls).contains { $0 is NSDatePicker || $0 is NSStepper })
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

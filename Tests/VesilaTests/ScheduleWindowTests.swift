import AppKit
import Testing
@testable import Vesila

@Suite("Schedule editor validation")
@MainActor
struct ScheduleWindowTests {
    @Test func invalidDraftsCannotSaveAndCancelDiscardsEdits() throws {
        _ = NSApplication.shared
        var saved: VesilaSchedule?
        let controller = ScheduleWindowController(calendar: scheduleCalendar) { saved = $0 }
        defer { controller.close() }
        controller.show(schedule: VesilaSchedule())
        let root = try #require(controller.window?.contentView)
        let views = descendants(of: root)
        let save = try #require(views.compactMap { $0 as? VesilaActionButton }.first { $0.accessibilityLabel() == "Save" })
        let cancel = try #require(views.compactMap { $0 as? VesilaActionButton }.first { $0.accessibilityLabel() == "Cancel" })
        let pills = views.compactMap { $0 as? MenuActionButton }
        #expect(pills.map { $0.accessibilityLabel() } == ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
        #expect(save.isEnabled)
        for pill in pills where pill.isSelected { pill.onClick?() }
        #expect(!save.isEnabled)
        #expect(!save.accessibilityPerformPress())
        #expect(saved == nil)
        #expect(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Select at least one day." })
        pills[0].onClick?()
        let pickers = views.compactMap { $0 as? NSDatePicker }
        let start = try #require(pickers.first { $0.accessibilityLabel() == "Start time" })
        let end = try #require(pickers.first { $0.accessibilityLabel() == "End time" })
        end.dateValue = start.dateValue
        _ = end.sendAction(end.action, to: end.target)
        #expect(!save.isEnabled)
        #expect(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "End time must be after start time." })
        end.dateValue = start.dateValue.addingTimeInterval(60 * 60)
        _ = end.sendAction(end.action, to: end.target)
        #expect(save.isEnabled)
        #expect(save.accessibilityPerformPress())
        #expect(saved == VesilaSchedule(days: [2], startMinute: 540, endMinute: 600))
        saved = nil
        controller.show(schedule: VesilaSchedule())
        pills[0].onClick?()
        #expect(cancel.accessibilityPerformPress())
        #expect(saved == nil)
        controller.show(schedule: VesilaSchedule())
        #expect(pills[0].isSelected) // a fresh draft replaces canceled edits
        root.layoutSubtreeIfNeeded()
        for view in [start, end, save, cancel] as [NSView] {
            #expect(root.bounds.contains(view.convert(view.bounds, to: root)))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

import Foundation
import Testing
@testable import Vesila

/// Fixed Gregorian calendar and wall-clock fixtures shared by schedule tests.
let scheduleCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    calendar.locale = Locale(identifier: "en_GB")
    calendar.firstWeekday = 2
    return calendar
}()

func scheduleDate(_ day: Int = 6, hour: Int, minute: Int = 0, month: Int = 10) -> Date {
    scheduleCalendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Schedule windows")
struct ScheduleTests {
    @Test func halfOpenWindowsAndWeekendGap() {
        let schedule = VesilaSchedule()
        let start = scheduleDate(hour: 9) // Tuesday
        let end = scheduleDate(hour: 18)
        #expect(schedule.window(containing: scheduleDate(hour: 8, minute: 59), calendar: scheduleCalendar) == nil)
        #expect(schedule.window(containing: start, calendar: scheduleCalendar) == DateInterval(start: start, end: end))
        #expect(schedule.window(containing: end, calendar: scheduleCalendar) == nil)
        #expect(schedule.nextBoundary(after: scheduleDate(hour: 8), calendar: scheduleCalendar) == start)
        #expect(schedule.nextBoundary(after: start, calendar: scheduleCalendar) == end)
        #expect(schedule.nextBoundary(after: end, calendar: scheduleCalendar) == scheduleDate(7, hour: 9))
        #expect(schedule.window(containing: scheduleDate(10, hour: 12), calendar: scheduleCalendar) == nil) // Saturday
        #expect(schedule.nextBoundary(after: scheduleDate(9, hour: 18), calendar: scheduleCalendar) == scheduleDate(12, hour: 9))
    }

    @Test func springDSTUsesWallClockTimes() throws {
        let schedule = VesilaSchedule(days: [1], startMinute: 60, endMinute: 4 * 60)
        let now = scheduleDate(8, hour: 3, month: 3) // DST advances at 02:00
        let window = try #require(schedule.window(containing: now, calendar: scheduleCalendar))
        #expect(window.start == scheduleDate(8, hour: 1, month: 3))
        #expect(window.end == scheduleDate(8, hour: 4, month: 3))
        #expect(window.duration == 2 * 60 * 60)
        #expect(schedule.nextBoundary(after: now, calendar: scheduleCalendar) == window.end)
        #expect(schedule.nextBoundary(after: window.end, calendar: scheduleCalendar) == scheduleDate(15, hour: 1, month: 3))
    }

    @Test func missingDSTTimeAdvancesAndRepeatedTimeUsesFirstOccurrence() throws {
        let spring = VesilaSchedule(days: [1], startMinute: 150, endMinute: 240)
        let window = try #require(spring.window(containing: scheduleDate(8, hour: 3, minute: 30, month: 3), calendar: scheduleCalendar))
        #expect(window.start == scheduleDate(8, hour: 3, month: 3))
        let autumn = VesilaSchedule(days: [1], startMinute: 60, endMinute: 120)
        let autumnWindow = try #require(autumn.window(containing: scheduleDate(1, hour: 1, minute: 30, month: 11), calendar: scheduleCalendar))
        #expect(autumnWindow.duration == 2 * 60 * 60)
    }

    @Test(arguments: [
        VesilaSchedule(days: []), VesilaSchedule(days: [0, 8]),
        VesilaSchedule(startMinute: -1), VesilaSchedule(endMinute: 1440),
        VesilaSchedule(startMinute: 600, endMinute: 600), VesilaSchedule(startMinute: 1080, endMinute: 540)
    ])
    func invalidSchedulesHaveNoWindows(schedule: VesilaSchedule) {
        #expect(!schedule.isValid)
        #expect(schedule.window(containing: scheduleDate(hour: 12), calendar: scheduleCalendar) == nil)
        #expect(schedule.nextBoundary(after: scheduleDate(hour: 12), calendar: scheduleCalendar) == nil)
    }

    @Test func weekdayOrderingRespectsLocaleFirstWeekday() {
        #expect(VesilaSchedule.orderedWeekdays(calendar: scheduleCalendar) == [2, 3, 4, 5, 6, 7, 1])
        var sundayFirst = scheduleCalendar
        sundayFirst.firstWeekday = 1
        #expect(VesilaSchedule.orderedWeekdays(calendar: sundayFirst) == [1, 2, 3, 4, 5, 6, 7])
    }
}

@Suite("Scheduled status strings")
struct ScheduledFormatterTests {
    private func line(_ state: VesilaState, at now: Date) -> String {
        VesilaFormatter.statusLine(for: state, at: now, calendar: scheduleCalendar, locale: Locale(identifier: "en_GB"))
    }

    @Test func eachScheduledStatus() {
        var state = VesilaState(preferences: VesilaPreferences(activationMode: .scheduled))
        #expect(line(state, at: scheduleDate(hour: 8)) == "Starts 09:00")
        #expect(line(state, at: scheduleDate(5, hour: 20)) == "Starts Tue 09:00")
        #expect(line(state, at: scheduleDate(10, hour: 12)) == "Starts Mon 09:00")
        state.evaluateSchedule(now: scheduleDate(hour: 10), calendar: scheduleCalendar, canActivate: true)
        #expect(line(state, at: scheduleDate(hour: 10)) == "Until 18:00")
        state.turnOffByUser(now: scheduleDate(hour: 10), calendar: scheduleCalendar)
        #expect(line(state, at: scheduleDate(hour: 10)) == "Paused until 18:00")
        #expect(line(state, at: scheduleDate(hour: 18)) == "Starts Wed 09:00")
        state.setSystemAwake(true, now: scheduleDate(hour: 20), calendar: scheduleCalendar)
        #expect(line(state, at: scheduleDate(hour: 20)) == "Until turned off")
    }

    @Test func manualStatusIsUnchanged() {
        var state = VesilaState()
        #expect(line(state, at: scheduleDate(hour: 10)) == "Inactive")
        state.setSystemAwake(true, now: scheduleDate(hour: 10))
        #expect(line(state, at: scheduleDate(hour: 10)) == "1h 0m remaining")
        state.selectDuration(.untilTurnedOff, now: scheduleDate(hour: 10))
        #expect(line(state, at: scheduleDate(hour: 10)) == "Until turned off")
    }

    @Test func scheduleSummaryUsesLocalizedTimesAndSpecialDayNames() {
        let locale = Locale(identifier: "en_GB")
        #expect(VesilaFormatter.scheduleSummary(VesilaSchedule(), calendar: scheduleCalendar, locale: locale) == "Weekdays · 09:00–18:00")
        #expect(VesilaFormatter.scheduleSummary(VesilaSchedule(days: Set(1...7)), calendar: scheduleCalendar, locale: locale) == "Every day · 09:00–18:00")
        #expect(VesilaFormatter.scheduleSummary(VesilaSchedule(days: [1, 3]), calendar: scheduleCalendar, locale: locale) == "Tue, Sun · 09:00–18:00")
    }
}

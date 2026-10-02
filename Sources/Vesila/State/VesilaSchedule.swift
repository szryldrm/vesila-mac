import Foundation

enum VesilaActivationMode: String, CaseIterable {
    // Raw values are persisted; don't rename the cases.
    case manual
    case scheduled

    var title: String { self == .manual ? "Manual" : "Scheduled" }
}

/// One same-day window on each selected Calendar weekday (1 = Sunday).
/// Dates are computed in the supplied calendar, including its time zone and DST rules.
struct VesilaSchedule: Equatable {
    var days: Set<Int> = [2, 3, 4, 5, 6]
    var startMinute = 9 * 60
    var endMinute = 18 * 60

    var isValid: Bool {
        !days.isEmpty && days.isSubset(of: Set(1...7)) &&
            (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute) && startMinute < endMinute
    }

    static func orderedWeekdays(calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// Half-open membership: the start belongs to the window; the end does not.
    func window(containing now: Date, calendar: Calendar) -> DateInterval? {
        guard let window = window(on: now, calendar: calendar), now >= window.start, now < window.end else { return nil }
        return window
    }

    func nextWindow(after now: Date, calendar: Calendar) -> DateInterval? {
        guard isValid else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let window = window(on: day, calendar: calendar), window.start > now else { continue }
            return window
        }
        return nil
    }

    func nextBoundary(after now: Date, calendar: Calendar) -> Date? {
        window(containing: now, calendar: calendar)?.end ?? nextWindow(after: now, calendar: calendar)?.start
    }

    private func window(on day: Date, calendar: Calendar) -> DateInterval? {
        guard isValid, days.contains(calendar.component(.weekday, from: day)) else { return nil }
        let midnight = calendar.startOfDay(for: day)
        // Missing times advance to the next valid wall-clock time; repeated times use the first
        // occurrence. Adding elapsed minutes to midnight would drift on a DST-transition day.
        guard let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0,
                                        of: midnight, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0,
                                      of: midnight, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              calendar.isDate(start, inSameDayAs: midnight), calendar.isDate(end, inSameDayAs: midnight), start < end
        else { return nil }
        return DateInterval(start: start, end: end)
    }
}

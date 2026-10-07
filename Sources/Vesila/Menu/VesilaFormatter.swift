import Foundation

enum VesilaFormatter {
    /// Manual shows the countdown; Scheduled shows the window end, pause, or next start.
    static func statusLine(for state: VesilaState, at now: Date, calendar: Calendar = .current,
                           locale: Locale = .current) -> String {
        if state.preferences.activationMode == .scheduled {
            if state.isSessionActive {
                if let end = state.expirationDate { return "Until \(time(end, calendar: calendar, locale: locale))" }
                return "Until turned off"
            }
            if let window = state.pausedWindow(at: now, calendar: calendar) {
                return "Paused until \(time(window.end, calendar: calendar, locale: locale))"
            }
            if state.preferences.schedule.window(containing: now, calendar: calendar) != nil {
                // Activation is unavailable while the system or session is interrupted.
                return "Inactive"
            }
            if let next = state.preferences.schedule.nextWindow(after: now, calendar: calendar) {
                let day = calendar.isDate(next.start, inSameDayAs: now) ? "" : "\(weekday(next.start, calendar: calendar, locale: locale)) "
                return "Starts \(day)\(time(next.start, calendar: calendar, locale: locale))"
            }
            return "Inactive"
        }
        guard state.isSessionActive else { return "Inactive" }
        guard let remaining = state.remainingTime(at: now) else { return "Until turned off" }
        return remainingDescription(remaining)
    }

    static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static func weekday(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    static func scheduleSummary(_ schedule: VesilaSchedule, calendar: Calendar = .current,
                                locale: Locale = .current) -> String {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let days: String
        if schedule.days == Set(1...7) {
            days = "Every day"
        } else if schedule.days == Set(2...6) {
            days = "Weekdays"
        } else {
            days = VesilaSchedule.orderedWeekdays(calendar: calendar)
                .filter { schedule.days.contains($0) }
                .map { localizedCalendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
        // A non-transition reference day formats the configured wall-clock minutes, not now.
        let day = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let start = calendar.date(bySettingHour: schedule.startMinute / 60, minute: schedule.startMinute % 60, second: 0, of: day)!
        let end = calendar.date(bySettingHour: schedule.endMinute / 60, minute: schedule.endMinute % 60, second: 0, of: day)!
        return "\(days) · \(time(start, calendar: calendar, locale: locale))–\(time(end, calendar: calendar, locale: locale))"
    }

    static func remainingDescription(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else if minutes > 0 {
            return "\(minutes)m remaining"
        } else {
            return "\(seconds)s remaining"
        }
    }
}

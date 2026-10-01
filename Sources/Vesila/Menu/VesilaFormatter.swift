import Foundation

enum VesilaFormatter {
    /// The status card's single line: "Inactive", "Until turned off", or the countdown.
    static func statusLine(for state: VesilaState, at now: Date) -> String {
        guard state.isSessionActive else { return "Inactive" }
        guard let remaining = state.remainingTime(at: now) else { return "Until turned off" }
        return remainingDescription(remaining)
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

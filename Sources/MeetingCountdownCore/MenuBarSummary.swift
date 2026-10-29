import Foundation

/// The short text shown next to the menu bar icon, e.g. "3.1 hrs till Design Review".
public enum MenuBarSummary {
    /// Longest meeting title shown before truncating with an ellipsis.
    public static let maxTitleLength = 24

    public static func text(for meeting: Meeting, now: Date) -> String {
        let seconds = Countdown.remainingSeconds(until: meeting.startDate, now: now)
        return "\(shortDuration(seconds: seconds)) till \(truncate(meeting.title))"
    }

    /// The badge beside a meeting in the menu: "in 12 min" before it starts, "12 min ago" after,
    /// "now" in its first minute.
    public static func badge(for meeting: Meeting, now: Date) -> String {
        guard meeting.startDate <= now else {
            return "in \(shortDuration(seconds: Countdown.remainingSeconds(until: meeting.startDate, now: now)))"
        }
        let elapsed = Int(now.timeIntervalSince(meeting.startDate))
        return elapsed < 60 ? "now" : "\(shortDuration(seconds: elapsed)) ago"
    }

    /// Picks the coarsest unit that still reads naturally: seconds under a minute,
    /// whole minutes under an hour, otherwise hours to one decimal place.
    /// Values are rounded down so the summary never overstates the time left.
    public static func shortDuration(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 {
            return "\(s) sec"
        }
        if s < 3600 {
            return "\(s / 60) min"
        }
        let tenths = s / 360
        let hours = tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
        return tenths == 10 ? "1 hr" : "\(hours) hrs"
    }

    public static func truncate(_ title: String, maxLength: Int = maxTitleLength) -> String {
        guard title.count > maxLength else { return title }
        let prefix = title.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces)
        return prefix + "…"
    }
}

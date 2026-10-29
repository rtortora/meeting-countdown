import Foundation

/// The short text shown next to the menu bar icon, e.g. "3.1 hrs till Design Review".
public enum MenuBarSummary {
    /// Longest meeting title shown before truncating with an ellipsis.
    public static let maxTitleLength = 24

    public static func text(for meeting: Meeting, now: Date) -> String {
        let seconds = Countdown.remainingSeconds(until: meeting.startDate, now: now)
        return "\(shortDuration(seconds: seconds)) till \(truncate(meeting.title))"
    }

    /// The line under a meeting in the menu: "In 23 min • 3:30 PM • Work". A meeting on another day
    /// names the day: "In 18.5 hrs • Tomorrow 9:00 AM • Work". It always starts with `countdown`.
    public static func menuSubtitle(
        for meeting: Meeting, now: Date, calendarName: String?, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        var start = meeting.startDate.formatted(format.hour().minute())
        if !calendar.isDate(meeting.startDate, inSameDayAs: now) {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let day =
                calendar.isDate(meeting.startDate, inSameDayAs: tomorrow)
                ? "Tomorrow" : meeting.startDate.formatted(format.weekday(.abbreviated).month(.abbreviated).day())
            start = "\(day) \(start)"
        }
        return [countdown(for: meeting, now: now), start, calendarName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    /// "In 12 min" before a meeting starts, "12 min ago" after, "Now" in its first minute.
    public static func countdown(for meeting: Meeting, now: Date) -> String {
        guard meeting.startDate <= now else {
            return "In \(shortDuration(seconds: Countdown.remainingSeconds(until: meeting.startDate, now: now)))"
        }
        let elapsed = Int(now.timeIntervalSince(meeting.startDate))
        return elapsed < 60 ? "Now" : "\(shortDuration(seconds: elapsed)) ago"
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

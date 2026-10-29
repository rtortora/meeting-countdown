import Foundation

public enum Countdown {
    /// How long before a meeting the overlay appears. Fixed in Phase 1.
    public static let leadTime: TimeInterval = 10 * 60

    /// How long before a meeting the overlay moves to the center of the screen.
    public static let centerLeadTime: TimeInterval = 60

    /// Seconds left until `start`, rounded up so the display never shows 0:00 while the meeting is still upcoming.
    public static func remainingSeconds(until start: Date, now: Date) -> Int {
        max(0, Int(start.timeIntervalSince(now).rounded(.up)))
    }

    /// The overlay is visible while the meeting is upcoming and within the lead time.
    public static func isOverlayVisible(start: Date, now: Date, leadTime: TimeInterval = leadTime) -> Bool {
        let remaining = start.timeIntervalSince(now)
        return remaining > 0 && remaining <= leadTime
    }

    /// The overlay is centered during the final `centerLeadTime` before the meeting.
    public static func isOverlayCentered(start: Date, now: Date, centerLeadTime: TimeInterval = centerLeadTime) -> Bool {
        let remaining = start.timeIntervalSince(now)
        return remaining > 0 && remaining <= centerLeadTime
    }

    /// Exponential ease-out: maps linear progress `t` in 0...1 to eased progress, fast start that settles gently.
    public static func easeOutExpo(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        // The curve only approaches 1, so snap the final frame to land exactly on target.
        return t == 1 ? 1 : 1 - pow(2, -10 * t)
    }

    /// Formats seconds as `m:ss`, or `h:mm:ss` when an hour or more remains.
    public static func format(seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

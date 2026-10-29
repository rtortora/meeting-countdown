import Foundation

/// A made-up day of meetings for demos and README screenshots, used instead of EventKit when the app is
/// launched with `--demo`. Times are relative to `anchor` (normally launch time), so the overlay is already
/// counting down when the app starts.
public struct DemoCalendar: Sendable {
    public struct CalendarSpec: Sendable {
        public let id: String
        public let title: String
        public let accountID: String
        public let accountTitle: String
        /// sRGB components, 0...1.
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    public static let launchArgument = "--demo"

    public let anchor: Date

    public init(anchor: Date) {
        self.anchor = anchor
    }

    public static let calendars: [CalendarSpec] = [
        CalendarSpec(
            id: "demo-work", title: "Work", accountID: "demo-google",
            accountTitle: "alex@example.com",
            red: 0.25, green: 0.52, blue: 0.96),
        CalendarSpec(
            id: "demo-clients", title: "Clients", accountID: "demo-google",
            accountTitle: "alex@example.com",
            red: 0.98, green: 0.62, blue: 0.13),
        CalendarSpec(
            id: "demo-personal", title: "Personal", accountID: "demo-icloud",
            accountTitle: "iCloud",
            red: 0.30, green: 0.78, blue: 0.40),
    ]

    public static func calendar(withID id: String) -> CalendarSpec? {
        calendars.first { $0.id == id }
    }

    /// The day's events, including some the app should skip (all-day, declined, cancelled).
    public func events() -> [CandidateEvent] {
        [
            event(
                "standup", "Team Standup", minutes: -8, calendar: "demo-work",
                notes: "Join Zoom Meeting\nhttps://us02web.zoom.us/j/81234567890?pwd=demo"),
            // The next meeting: about four and a half minutes out, so the overlay is up.
            event(
                "design-review", "Design Review", minutes: 4.5, calendar: "demo-work",
                notes: """
                    -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
                    Join with Google Meet: https://meet.google.com/abc-defg-hij
                    Join by phone: https://tel.meet/abc-defg-hij?pin=1234567890
                    -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
                    """),
            event(
                "acme", "Acme Quarterly Check-in", minutes: 35, calendar: "demo-clients",
                location:
                    "https://teams.microsoft.com/l/meetup-join/19%3ameeting_demo%40thread.v2/0"),
            event(
                "sam", "Meet with Sam", minutes: 70, calendar: "demo-personal",
                location: "Blue Bottle Coffee"),
            event(
                "planning", "Sprint Planning", minutes: 150, calendar: "demo-work",
                notes: "https://meet.google.com/xyz-uvwx-rst"),
            // Skipped: not meetings the user is going to.
            event(
                "offsite", "Team Offsite Prep", minutes: -60, calendar: "demo-work", isAllDay: true),
            event(
                "sync", "Optional Architecture Sync", minutes: 15, calendar: "demo-work",
                isDeclined: true),
            event(
                "retro", "Retro (moved to Friday)", minutes: 20, calendar: "demo-work",
                isCanceled: true),
        ]
    }

    private func event(
        _ id: String, _ title: String, minutes: Double, calendar: String, location: String? = nil,
        notes: String? = nil, isAllDay: Bool = false, isDeclined: Bool = false,
        isCanceled: Bool = false
    ) -> CandidateEvent {
        CandidateEvent(
            id: "demo-\(id)",
            title: title,
            startDate: anchor.addingTimeInterval(minutes * 60),
            isAllDay: isAllDay,
            isDeclined: isDeclined,
            isCanceled: isCanceled,
            linkSources: [location, notes].compactMap { $0 },
            accountID: Self.calendar(withID: calendar)?.accountID,
            calendarID: calendar,
            calendarItemID: nil
        )
    }
}

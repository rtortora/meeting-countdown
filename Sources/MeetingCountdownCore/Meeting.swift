import Foundation

/// A meeting the app may count down to.
public struct Meeting: Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let videoLink: VideoLink?
    /// The calendar account (EventKit source) the event came from; picks how its call opens.
    public let accountID: String?
    /// The EventKit calendar the event is on; the menu shows its color.
    public let calendarID: String?
    /// EventKit's `calendarItemIdentifier`, for showing the event in Calendar.app.
    public let calendarItemID: String?

    public init(
        id: String, title: String, startDate: Date, videoLink: VideoLink? = nil, accountID: String? = nil,
        calendarID: String? = nil, calendarItemID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.videoLink = videoLink
        self.accountID = accountID
        self.calendarID = calendarID
        self.calendarItemID = calendarItemID
    }
}

/// A calendar event reduced to the facts needed to decide whether it counts as a meeting.
/// Built from `EKEvent` in the app target; kept EventKit-free so selection logic is testable.
public struct CandidateEvent: Sendable {
    public let id: String
    public let title: String?
    public let startDate: Date
    public let isAllDay: Bool
    public let isDeclined: Bool
    public let isCanceled: Bool
    /// Invite text that may hold a video call link, most specific first (URL, location, notes).
    /// Only scanned for the meeting that gets picked.
    public let linkSources: [String]
    public let accountID: String?
    public let calendarID: String?
    public let calendarItemID: String?

    public init(
        id: String,
        title: String?,
        startDate: Date,
        isAllDay: Bool = false,
        isDeclined: Bool = false,
        isCanceled: Bool = false,
        linkSources: [String] = [],
        accountID: String? = nil,
        calendarID: String? = nil,
        calendarItemID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isCanceled = isCanceled
        self.linkSources = linkSources
        self.accountID = accountID
        self.calendarID = calendarID
        self.calendarItemID = calendarItemID
    }
}

/// The meetings the menu lists: those that started recently, the next one, and the rest coming up soon.
public struct MeetingSchedule: Equatable, Sendable {
    /// How long after its start a meeting still shows as started.
    public static let lookBack: TimeInterval = 30 * 60
    /// How far ahead meetings after the next one are listed. The next meeting shows however far off it is.
    public static let lookAhead: TimeInterval = 90 * 60

    /// Started at or before now, within `lookBack`, earliest first.
    public let recent: [Meeting]
    public let next: Meeting?
    /// Starting after `next`, within `lookAhead`, earliest first.
    public let later: [Meeting]

    public static let empty = MeetingSchedule(recent: [], next: nil, later: [])

    public init(recent: [Meeting], next: Meeting?, later: [Meeting]) {
        self.recent = recent
        self.next = next
        self.later = later
    }

    /// Sorts `meetings` into the three groups, dropping those outside the windows.
    public init(
        meetings: [Meeting], now: Date, lookBack: TimeInterval = lookBack, lookAhead: TimeInterval = lookAhead
    ) {
        let sorted = meetings.sorted(by: MeetingSelector.isEarlier)
        recent = sorted.filter { $0.startDate <= now && $0.startDate >= now - lookBack }
        let upcoming = sorted.filter { $0.startDate > now }
        next = upcoming.first
        later = upcoming.dropFirst().filter { $0.startDate <= now + lookAhead }
    }
}

public enum MeetingSelector {
    public static let untitledTitle = "Untitled event"

    /// The earliest event starting strictly after `now`, ignoring all-day, declined and cancelled events.
    public static func nextMeeting(from events: [CandidateEvent], now: Date) -> Meeting? {
        events
            .filter { isMeeting($0) && $0.startDate > now }
            .min(by: isEarlier)
            .map(meeting(from:))
    }

    /// The menu's meetings, ignoring all-day, declined and cancelled events. Links are only looked for in
    /// the events that make it in.
    public static func schedule(
        from events: [CandidateEvent], now: Date, lookBack: TimeInterval = MeetingSchedule.lookBack,
        lookAhead: TimeInterval = MeetingSchedule.lookAhead
    ) -> MeetingSchedule {
        let eligible = events.filter(isMeeting).sorted(by: isEarlier)
        let nextID = eligible.first { $0.startDate > now }?.id
        let listed = eligible.filter { event in
            event.id == nextID || (event.startDate >= now - lookBack && event.startDate <= now + lookAhead)
        }
        return MeetingSchedule(meetings: listed.map(meeting(from:)), now: now, lookBack: lookBack, lookAhead: lookAhead)
    }

    private static func isMeeting(_ event: CandidateEvent) -> Bool {
        !event.isAllDay && !event.isDeclined && !event.isCanceled
    }

    private static func isEarlier(_ lhs: CandidateEvent, _ rhs: CandidateEvent) -> Bool {
        lhs.startDate != rhs.startDate ? lhs.startDate < rhs.startDate : lhs.id < rhs.id
    }

    static func isEarlier(_ lhs: Meeting, _ rhs: Meeting) -> Bool {
        lhs.startDate != rhs.startDate ? lhs.startDate < rhs.startDate : lhs.id < rhs.id
    }

    private static func meeting(from event: CandidateEvent) -> Meeting {
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Meeting(
            id: event.id,
            title: title.isEmpty ? untitledTitle : title,
            startDate: event.startDate,
            videoLink: VideoLinkDetector.detect(in: event.linkSources),
            accountID: event.accountID,
            calendarID: event.calendarID,
            calendarItemID: event.calendarItemID
        )
    }
}

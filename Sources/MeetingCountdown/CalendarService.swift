import AppKit
import EventKit
import MeetingCountdownCore

/// A calendar the user can turn on or off in Settings.
struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let color: CGColor?
}

/// The calendars of one account (iCloud, a Google account, On My Mac…).
struct CalendarAccount: Identifiable {
    let id: String
    let title: String
    let calendars: [CalendarInfo]
}

/// Wraps EventKit: authorization, finding upcoming meetings in the chosen calendars, and change notifications.
@MainActor
final class CalendarService {
    enum Access {
        case notDetermined
        case granted
        case denied
    }

    /// How far ahead to look for the next meeting.
    private static let searchWindow: TimeInterval = 7 * 24 * 60 * 60

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    /// Set when launched with `--demo`: a made-up schedule stands in for the user's calendars.
    private let demo = ProcessInfo.processInfo.arguments.contains(DemoCalendar.launchArgument)
        ? DemoCalendar(anchor: Date()) : nil

    /// Called on the main actor whenever the calendar database changes (events added, moved, deleted, accounts synced).
    var onChange: (() -> Void)?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    var access: Access {
        if demo != nil { return .granted }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .granted
        case .notDetermined:
            return .notDetermined
        // Write-only access can't read events, so it's as good as denied for us.
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAccess(completion: @escaping @MainActor (Access) -> Void) {
        store.requestFullAccessToEvents { [weak self] _, error in
            if let error {
                NSLog("Calendar access request failed: \(error.localizedDescription)")
            }
            Task { @MainActor in
                guard let self else { return }
                // Pick up calendars that only became visible after access was granted.
                self.store.reset()
                completion(self.access)
            }
        }
    }

    /// Drops EventKit's cached accounts and calendars and asks remote accounts to sync. Anything the sync
    /// turns up arrives later through `onChange`.
    func refreshAccounts() {
        guard demo == nil, access == .granted else { return }
        store.reset()
        store.refreshSourcesIfNecessary()
    }

    /// Every event calendar, grouped by account, accounts and calendars sorted by name.
    func accounts() -> [CalendarAccount] {
        if demo != nil { return Self.demoAccounts() }
        guard access == .granted else { return [] }
        let bySource = Dictionary(grouping: store.calendars(for: .event)) { $0.source.sourceIdentifier }
        return bySource.values
            .map { calendars in
                CalendarAccount(
                    id: calendars[0].source.sourceIdentifier,
                    title: calendars[0].source.title,
                    calendars: calendars
                        .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, color: $0.cgColor) }
                        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The meetings the menu lists, plus the next one even if it's days away.
    func schedule(now: Date = Date(), selection: CalendarSelection) -> MeetingSchedule {
        if let demo {
            let events = demo.events().filter { $0.calendarID.map(selection.includes) ?? true }
            return MeetingSelector.schedule(from: events, now: now)
        }
        guard access == .granted else { return .empty }
        let calendars = store.calendars(for: .event).filter { selection.includes($0.calendarIdentifier) }
        // Every calendar turned off: nothing to watch (and EventKit isn't asked about an empty list).
        guard !calendars.isEmpty else { return .empty }
        let predicate = store.predicateForEvents(
            // Overlap, not start time: this also returns longer events that started earlier, which
            // `MeetingSelector` drops.
            withStart: now - MeetingSchedule.lookBack,
            end: now.addingTimeInterval(Self.searchWindow),
            calendars: calendars
        )
        let candidates = store.events(matching: predicate).map { event in
            CandidateEvent(
                // Occurrences of a recurring event share an identifier, so qualify it with the start time.
                id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(event.startDate.timeIntervalSinceReferenceDate)",
                title: event.title,
                startDate: event.startDate,
                isAllDay: event.isAllDay,
                isDeclined: event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined,
                isCanceled: event.status == .canceled,
                linkSources: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 },
                accountID: event.calendar.source.sourceIdentifier,
                calendarID: event.calendar.calendarIdentifier,
                calendarItemID: event.calendarItemIdentifier
            )
        }
        return MeetingSelector.schedule(from: candidates, now: now)
    }

    func title(ofCalendar id: String) -> String? {
        if demo != nil {
            return DemoCalendar.calendar(withID: id)?.title
        }
        guard access == .granted else { return nil }
        return store.calendar(withIdentifier: id)?.title
    }

    private static func demoAccounts() -> [CalendarAccount] {
        Dictionary(grouping: DemoCalendar.calendars, by: \.accountID).values
            .map { calendars in
                CalendarAccount(
                    id: calendars[0].accountID,
                    title: calendars[0].accountTitle,
                    calendars: calendars.map {
                        CalendarInfo(id: $0.id, title: $0.title, color: color(of: $0))
                    })
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func color(of calendar: DemoCalendar.CalendarSpec) -> CGColor {
        CGColor(srgbRed: calendar.red, green: calendar.green, blue: calendar.blue, alpha: 1)
    }

    /// Shows the event in Calendar.app, or just opens Calendar if that fails.
    /// `ical://ekevent/` isn't documented by Apple, but Calendar.app handles it.
    static func showInCalendar(_ meeting: Meeting) {
        if let id = meeting.calendarItemID?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"),
            NSWorkspace.shared.open(url)
        {
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }
}

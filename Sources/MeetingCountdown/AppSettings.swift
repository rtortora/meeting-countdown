import Foundation
import MeetingCountdownCore
import Observation

/// The user's choices from the Settings window, saved in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let excludedCalendarIDs = "excludedCalendarIDs"
        static let videoLinkPreferences = "videoLinkPreferencesByAccount"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after any setting changes, so the next meeting can be re-picked.
    @ObservationIgnored var onChange: () -> Void = {}

    var calendarSelection: CalendarSelection {
        didSet {
            defaults.set(calendarSelection.excludedIDs.sorted(), forKey: Key.excludedCalendarIDs)
            onChange()
        }
    }

    /// Keyed by calendar account (EventKit source identifier); accounts not listed use `.standard`.
    var videoLinkPreferences: [String: VideoLinkPreference] {
        didSet {
            defaults.set(videoLinkPreferences.mapValues(\.rawValue), forKey: Key.videoLinkPreferences)
            onChange()
        }
    }

    func videoLinkPreference(forAccount accountID: String?) -> VideoLinkPreference {
        accountID.flatMap { videoLinkPreferences[$0] } ?? .standard
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        calendarSelection = CalendarSelection(
            excludedIDs: Set(defaults.stringArray(forKey: Key.excludedCalendarIDs) ?? []))
        let stored = defaults.dictionary(forKey: Key.videoLinkPreferences) as? [String: String] ?? [:]
        videoLinkPreferences = stored.compactMapValues(VideoLinkPreference.init(rawValue:))
    }
}

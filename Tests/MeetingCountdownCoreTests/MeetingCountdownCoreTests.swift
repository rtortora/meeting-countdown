import XCTest
@testable import MeetingCountdownCore

final class MeetingSelectorTests: XCTestCase {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testPicksEarliestUpcomingEvent() {
        let events = [
            CandidateEvent(id: "b", title: "Later", startDate: now + 3600),
            CandidateEvent(id: "a", title: "Sooner", startDate: now + 300),
        ]
        XCTAssertEqual(MeetingSelector.nextMeeting(from: events, now: now)?.id, "a")
    }

    func testSkipsAllDayDeclinedCanceledAndStartedEvents() {
        let events = [
            CandidateEvent(id: "allday", title: "Holiday", startDate: now + 10, isAllDay: true),
            CandidateEvent(id: "declined", title: "Nope", startDate: now + 20, isDeclined: true),
            CandidateEvent(id: "canceled", title: "Gone", startDate: now + 30, isCanceled: true),
            CandidateEvent(id: "started", title: "In progress", startDate: now - 60),
            CandidateEvent(id: "now", title: "Starting now", startDate: now),
            CandidateEvent(id: "ok", title: "Real", startDate: now + 600),
        ]
        XCTAssertEqual(MeetingSelector.nextMeeting(from: events, now: now)?.id, "ok")
    }

    func testCarriesTheCalendarAccount() {
        let events = [CandidateEvent(id: "a", title: "Sync", startDate: now + 60, accountID: "work-account")]
        XCTAssertEqual(MeetingSelector.nextMeeting(from: events, now: now)?.accountID, "work-account")
    }

    func testCarriesTheCalendar() {
        let events = [
            CandidateEvent(
                id: "a", title: "Sync", startDate: now + 60, calendarID: "work-calendar", calendarItemID: "item-1")
        ]
        let meeting = MeetingSelector.nextMeeting(from: events, now: now)
        XCTAssertEqual(meeting?.calendarID, "work-calendar")
        XCTAssertEqual(meeting?.calendarItemID, "item-1")
    }

    func testReturnsNilWhenNothingUpcoming() {
        XCTAssertNil(MeetingSelector.nextMeeting(from: [], now: now))
    }

    func testTiesBreakDeterministicallyById() {
        let events = [
            CandidateEvent(id: "z", title: "Z", startDate: now + 60),
            CandidateEvent(id: "m", title: "M", startDate: now + 60),
        ]
        XCTAssertEqual(MeetingSelector.nextMeeting(from: events, now: now)?.id, "m")
    }

    func testBlankTitleFallsBack() {
        let events = [CandidateEvent(id: "a", title: "  ", startDate: now + 60)]
        XCTAssertEqual(MeetingSelector.nextMeeting(from: events, now: now)?.title, MeetingSelector.untitledTitle)
    }
}

final class MeetingScheduleTests: XCTestCase {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testGroupsRecentNextAndLater() {
        let events = [
            CandidateEvent(id: "later", title: "Later", startDate: now + 80 * 60),
            CandidateEvent(id: "tooOld", title: "Too old", startDate: now - 31 * 60),
            CandidateEvent(id: "recent", title: "Recent", startDate: now - 30 * 60),
            CandidateEvent(id: "now", title: "Starting now", startDate: now),
            CandidateEvent(id: "next", title: "Next", startDate: now + 5 * 60),
            CandidateEvent(id: "tooFar", title: "Too far", startDate: now + 91 * 60),
            CandidateEvent(id: "declined", title: "Nope", startDate: now + 10 * 60, isDeclined: true),
        ]
        let schedule = MeetingSelector.schedule(from: events, now: now)
        XCTAssertEqual(schedule.recent.map(\.id), ["recent", "now"])
        XCTAssertEqual(schedule.next?.id, "next")
        XCTAssertEqual(schedule.later.map(\.id), ["later"])
    }

    func testNextShowsHoweverFarOff() {
        let events = [CandidateEvent(id: "a", title: "Tomorrow", startDate: now + 24 * 3600)]
        let schedule = MeetingSelector.schedule(from: events, now: now)
        XCTAssertEqual(schedule.next?.id, "a")
        XCTAssertEqual(schedule.later, [])
    }

    func testEachMeetingCarriesItsVideoLink() {
        let events = [
            CandidateEvent(id: "a", title: "A", startDate: now - 60, linkSources: ["https://meet.google.com/abc-defg-hij"]),
            CandidateEvent(id: "b", title: "B", startDate: now + 60, linkSources: ["https://zoom.us/j/123456789"]),
            CandidateEvent(id: "c", title: "C", startDate: now + 120),
        ]
        let schedule = MeetingSelector.schedule(from: events, now: now)
        XCTAssertEqual(schedule.recent.first?.videoLink?.provider, .googleMeet)
        XCTAssertEqual(schedule.next?.videoLink?.provider, .zoom)
        XCTAssertNil(schedule.later.first?.videoLink)
    }
}

final class MenuBarSummaryTests: XCTestCase {
    func testShortDurationUnits() {
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 0), "0 sec")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 45), "45 sec")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 60), "1 min")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 3599), "59 min")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 3600), "1 hr")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 3959), "1 hr")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 3960), "1.1 hrs")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 7200), "2 hrs")
        XCTAssertEqual(MenuBarSummary.shortDuration(seconds: 11_400), "3.1 hrs")
    }

    func testTruncate() {
        XCTAssertEqual(MenuBarSummary.truncate("Standup"), "Standup")
        XCTAssertEqual(MenuBarSummary.truncate(String(repeating: "a", count: 24)), String(repeating: "a", count: 24))
        XCTAssertEqual(MenuBarSummary.truncate("Quarterly planning review with leadership"), "Quarterly planning revi…")
        XCTAssertEqual(MenuBarSummary.truncate("Quarterly planning      review"), "Quarterly planning…")
    }

    func testText() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let meeting = Meeting(id: "a", title: "Design Review", startDate: now + 11_400)
        XCTAssertEqual(MenuBarSummary.text(for: meeting, now: now), "3.1 hrs till Design Review")
    }

    func testBadge() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(MenuBarSummary.badge(for: Meeting(id: "a", title: "x", startDate: now + 720), now: now), "in 12 min")
        XCTAssertEqual(MenuBarSummary.badge(for: Meeting(id: "a", title: "x", startDate: now + 11_400), now: now), "in 3.1 hrs")
        XCTAssertEqual(MenuBarSummary.badge(for: Meeting(id: "a", title: "x", startDate: now), now: now), "now")
        XCTAssertEqual(MenuBarSummary.badge(for: Meeting(id: "a", title: "x", startDate: now - 59), now: now), "now")
        XCTAssertEqual(MenuBarSummary.badge(for: Meeting(id: "a", title: "x", startDate: now - 720), now: now), "12 min ago")
    }
}

final class CountdownTests: XCTestCase {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testOverlayVisibilityWindow() {
        XCTAssertFalse(Countdown.isOverlayVisible(start: start, now: start - 601))
        XCTAssertTrue(Countdown.isOverlayVisible(start: start, now: start - 600))
        XCTAssertTrue(Countdown.isOverlayVisible(start: start, now: start - 0.5))
        XCTAssertFalse(Countdown.isOverlayVisible(start: start, now: start))
        XCTAssertFalse(Countdown.isOverlayVisible(start: start, now: start + 1))
    }

    func testOverlayCenteredWindow() {
        XCTAssertFalse(Countdown.isOverlayCentered(start: start, now: start - 61))
        XCTAssertTrue(Countdown.isOverlayCentered(start: start, now: start - 60))
        XCTAssertTrue(Countdown.isOverlayCentered(start: start, now: start - 0.5))
        XCTAssertFalse(Countdown.isOverlayCentered(start: start, now: start))
    }

    func testEaseOutExpo() {
        XCTAssertEqual(Countdown.easeOutExpo(0), 0)
        XCTAssertEqual(Countdown.easeOutExpo(0.1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Countdown.easeOutExpo(0.5), 0.96875, accuracy: 1e-12)
        XCTAssertEqual(Countdown.easeOutExpo(1), 1)
        // Out-of-range progress clamps instead of overshooting.
        XCTAssertEqual(Countdown.easeOutExpo(-1), 0)
        XCTAssertEqual(Countdown.easeOutExpo(2), 1)
    }

    func testRemainingRoundsUp() {
        XCTAssertEqual(Countdown.remainingSeconds(until: start, now: start - 0.2), 1)
        XCTAssertEqual(Countdown.remainingSeconds(until: start, now: start - 59.5), 60)
        XCTAssertEqual(Countdown.remainingSeconds(until: start, now: start + 5), 0)
    }

    func testFormat() {
        XCTAssertEqual(Countdown.format(seconds: 0), "0:00")
        XCTAssertEqual(Countdown.format(seconds: 9), "0:09")
        XCTAssertEqual(Countdown.format(seconds: 600), "10:00")
        XCTAssertEqual(Countdown.format(seconds: 3725), "1:02:05")
    }
}

final class VideoLinkDetectorTests: XCTestCase {
    /// Google's conference block as it appears in a synced invite's notes.
    let googleNotes = """
        Agenda: weekly sync
        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        Join with Google Meet: https://meet.google.com/qrs-tuvw-xyz
        Or dial: (US) +1 555-010-0199 PIN: 123456789#
        More phone numbers: https://tel.meet/qrs-tuvw-xyz?pin=1234567890123&hs=7

        Learn more about Meet at: https://support.google.com/a/users/answer/9282720

        Please do not edit this section.
        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        """

    func testFindsGoogleMeetInNotes() {
        let link = VideoLinkDetector.detect(in: [googleNotes])
        XCTAssertEqual(link?.provider, .googleMeet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/qrs-tuvw-xyz")
        XCTAssertNil(link?.appURL)
    }

    func testIgnoresNonCallLinks() {
        let texts = [
            "message:%3Cexample-message-id@mail.gmail.com%3E",
            "sms://open?message-guid=00000000-0000-0000-0000-000000000000",
            "Building 2-Lakeview (8) [TV, Whiteboard]",
            "More phone numbers: https://tel.meet/qrs-tuvw-xyz?pin=1 https://support.google.com/a/users/answer/9282720",
            "Zoom help: https://support.zoom.us/hc/en-us https://zoom.us/download",
            "https://meet.google.com/",
        ]
        XCTAssertNil(VideoLinkDetector.detect(in: texts))
    }

    func testEarlierFieldsWin() {
        let link = VideoLinkDetector.detect(in: ["https://acme.zoom.us/j/123456789", googleNotes])
        XCTAssertEqual(link?.provider, .zoom)
    }

    func testZoomInLocationOpensApp() {
        let link = VideoLinkDetector.detect(in: ["https://us02web.zoom.us/j/85512345678?pwd=aBcD1234.1"])
        XCTAssertEqual(link?.provider, .zoom)
        XCTAssertEqual(
            link?.appURL?.absoluteString,
            "zoommtg://us02web.zoom.us/join?action=join&confno=85512345678&pwd=aBcD1234.1")
    }

    func testZoomVanityLinkHasNoAppURL() {
        let link = VideoLinkDetector.detect(in: ["https://zoom.us/my/jane.doe"])
        XCTAssertEqual(link?.provider, .zoom)
        XCTAssertNil(link?.appURL)
    }

    func testTeamsMeetupJoinOpensApp() {
        let notes = """
            Microsoft Teams meeting
            Join on your computer, mobile app or room device
            Click here to join the meeting<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d>
            """
        let link = VideoLinkDetector.detect(in: [notes])
        XCTAssertEqual(link?.provider, .teams)
        XCTAssertEqual(
            link?.appURL?.absoluteString,
            "msteams:/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d")
    }

    func testFindsLinkInsideHTMLAndWithoutScheme() {
        let html = #"<p>Join: <a href="https://meet.google.com/abc-defg-hij?authuser=0">meeting</a></p>"#
        XCTAssertEqual(VideoLinkDetector.detect(in: [html])?.url.host, "meet.google.com")
        let bare = VideoLinkDetector.detect(in: ["Call at meet.google.com/abc-defg-hij"])
        XCTAssertEqual(bare?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testOtherProviders() {
        let cases: [(String, VideoLink.Provider)] = [
            ("https://acme.webex.com/meet/jdoe", .webex),
            ("https://acme.webex.com/acme/j.php?MTID=m123", .webex),
            ("https://whereby.com/standup-room", .whereby),
            ("https://app.chime.aws/meetings/1234567890", .chime),
            ("https://meet.goto.com/123456789", .goTo),
            ("https://teams.live.com/meet/9381234567890?p=abc", .teams),
            ("https://meet.jit.si/OurStandup", .jitsi),
        ]
        for (text, provider) in cases {
            XCTAssertEqual(VideoLinkDetector.detect(in: [text])?.provider, provider, text)
        }
    }

    func testSelectedMeetingCarriesVideoLink() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let events = [CandidateEvent(id: "a", title: "1:1", startDate: now + 60, linkSources: [googleNotes])]
        XCTAssertEqual(MeetingSelector.nextMeeting(from: events, now: now)?.videoLink?.provider, .googleMeet)
    }
}

final class WebAppWindowChooserTests: XCTestCase {
    let target = URL(string: "https://meet.google.com/qrs-tuvw-xyz")!

    func testReusesIdleWindowOnSameSite() {
        let windows = [
            (id: 1, url: URL(string: "https://drive.google.com/drive/home")!),
            (id: 2, url: URL(string: "https://meet.google.com/home?lfhs=2")!),
        ]
        XCTAssertEqual(WebAppWindowChooser.choose(for: target, windows: windows), .navigate(windowID: 2))
    }

    func testFocusesWindowAlreadyInThisCall() {
        let windows = [
            (id: 1, url: URL(string: "https://meet.google.com/landing")!),
            (id: 2, url: URL(string: "https://meet.google.com/qrs-tuvw-xyz?authuser=0")!),
        ]
        XCTAssertEqual(WebAppWindowChooser.choose(for: target, windows: windows), .focus(windowID: 2))
    }

    func testNeverTakesOverAnotherCall() {
        let windows = [(id: 1, url: URL(string: "https://meet.google.com/abc-defg-hij")!)]
        XCTAssertNil(WebAppWindowChooser.choose(for: target, windows: windows))
    }

    func testNoWindowsOnSite() {
        let windows = [(id: 1, url: URL(string: "https://kagi.com/search?q=meet")!)]
        XCTAssertNil(WebAppWindowChooser.choose(for: target, windows: windows))
    }
}

final class VideoLinkPreferenceTests: XCTestCase {
    func testRoundTripsThroughRawValue() {
        for preference: VideoLinkPreference in [.meetApp, .defaultBrowser, .chromeProfile(directory: "Profile 3")] {
            XCTAssertEqual(VideoLinkPreference(rawValue: preference.rawValue), preference)
        }
    }

    func testRejectsUnknownValues() {
        XCTAssertNil(VideoLinkPreference(rawValue: "safari"))
        XCTAssertNil(VideoLinkPreference(rawValue: "chromeProfile:"))
    }
}

final class ChromeProfileTests: XCTestCase {
    func testReadsProfilesInPickerOrder() {
        let localState = Data("""
            {"profile": {
                "profiles_order": ["Default", "Profile 3", "Profile 1"],
                "info_cache": {
                    "Profile 1": {"name": "Acme", "user_name": "me@work.example"},
                    "Default": {"name": "Personal", "user_name": "me@gmail.com"},
                    "Profile 3": {"name": "Work", "user_name": ""},
                    "Profile 9": {"name": "Hidden", "is_omitted_from_profile_list": true},
                    "Profile 7": {"name": "Unordered"}
                }
            }}
            """.utf8)
        let profiles = ChromeProfile.profiles(fromLocalState: localState)
        XCTAssertEqual(profiles.map(\.directory), ["Default", "Profile 3", "Profile 1", "Profile 7"])
        XCTAssertEqual(profiles.map(\.displayName), ["Personal (me@gmail.com)", "Work", "Acme (me@work.example)", "Unordered"])
    }

    func testMalformedLocalStateHasNoProfiles() {
        XCTAssertEqual(ChromeProfile.profiles(fromLocalState: Data("{}".utf8)), [])
        XCTAssertEqual(ChromeProfile.profiles(fromLocalState: Data("not json".utf8)), [])
    }
}

final class CalendarSelectionTests: XCTestCase {
    func testCalendarsAreIncludedUntilTurnedOff() {
        var selection = CalendarSelection()
        XCTAssertTrue(selection.includes("new-calendar"))
        selection.setIncluded(false, calendarID: "holidays")
        XCTAssertFalse(selection.includes("holidays"))
        XCTAssertTrue(selection.includes("work"))
        selection.setIncluded(true, calendarID: "holidays")
        XCTAssertTrue(selection.includes("holidays"))
        XCTAssertEqual(selection.excludedIDs, [])
    }
}

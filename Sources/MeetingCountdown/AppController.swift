import AppKit
import MeetingCountdownCore

/// Owns the menu bar item, the overlay, and the tick loop that ties them to the calendar.
@MainActor
final class AppController: NSObject, NSMenuDelegate {
    /// Fine-grained ticks so the displayed second flips close to the real boundary;
    /// the UI is only touched when the rendered text actually changes.
    private static let tickInterval: TimeInterval = 0.25
    /// Safety-net refresh in case a change notification is missed (and to pick up access granted in Settings).
    private static let periodicRefreshInterval: TimeInterval = 60

    private let calendar = CalendarService()
    private let settings = AppSettings()
    private lazy var settingsWindow = SettingsWindowController(settings: settings, calendar: calendar)
    private let overlay = OverlayController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    /// What the menu lists; its `next` drives the status title and the overlay.
    private var schedule = MeetingSchedule.empty
    private var nextMeeting: Meeting? { schedule.next }
    /// The meeting the user already joined from here; its overlay stays hidden so it doesn't cover the call.
    private var joinedMeetingID: String?
    private var lastRefresh = Date.distantPast
    /// While the menu is open, rebuilding it would swap out the item under the pointer and swallow the click,
    /// so rebuilds wait until it closes.
    private var isMenuOpen = false
    private var menuNeedsRebuild = false
    /// The meeting rows, kept so their "in 12 min" badges can count down while the menu is open.
    private var meetingRows: [MeetingMenuRowView] = []
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "calendar.badge.clock",
                accessibilityDescription: "Meeting Countdown")
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        calendar.onChange = { [weak self] in
            self?.refresh()
            self?.settingsWindow.reload()
        }
        settings.onChange = { [weak self] in self?.refresh() }
        overlay.onJoin = { [weak self] in self?.joinNextMeeting() }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        // .common so the countdown keeps running while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        switch calendar.access {
        case .notDetermined:
            calendar.requestAccess { [weak self] _ in self?.refresh() }
        case .granted, .denied:
            refresh()
        }

        // For screenshots (with `--demo`): open the menu once the app has settled.
        if ProcessInfo.processInfo.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.statusItem.button?.performClick(nil)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.settingsWindow.show()
            }
        }
    }

    // MARK: - State

    private func refresh() {
        lastRefresh = Date()
        schedule = calendar.schedule(now: lastRefresh, selection: settings.calendarSelection)
        rebuildMenu()
        tick()
    }

    private func tick() {
        let now = Date()
        if let meeting = nextMeeting, meeting.startDate <= now {
            // The meeting just started: hide the overlay and move on to the next one.
            refresh()
            return
        }
        if now.timeIntervalSince(lastRefresh) >= Self.periodicRefreshInterval {
            refresh()
            return
        }
        updateStatusTitle(now: now)
        for row in meetingRows { row.update(now: now) }
        updateOverlay(now: now)
    }

    private func updateStatusTitle(now: Date) {
        guard let button = statusItem.button else { return }
        let title = nextMeeting.map { " " + MenuBarSummary.text(for: $0, now: now) } ?? ""
        if button.title != title {
            button.title = title
        }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }

    private func updateOverlay(now: Date) {
        guard let meeting = nextMeeting,
            meeting.id != joinedMeetingID,
            Countdown.isOverlayVisible(start: meeting.startDate, now: now)
        else {
            overlay.hide()
            return
        }
        let remaining = Countdown.format(
            seconds: Countdown.remainingSeconds(until: meeting.startDate, now: now))
        overlay.show(
            title: meeting.title,
            remaining: remaining,
            joinHelp: meeting.videoLink.map(Self.joinTitle),
            centered: Countdown.isOverlayCentered(start: meeting.startDate, now: now)
        )
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Re-read on open so a permission change made in System Settings shows up immediately.
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if menuNeedsRebuild { rebuildMenu() }
    }

    private func rebuildMenu() {
        guard !isMenuOpen else {
            menuNeedsRebuild = true
            return
        }
        menuNeedsRebuild = false
        menu.removeAllItems()
        meetingRows = []

        switch calendar.access {
        case .granted:
            addMeetingSection(.sectionHeader(title: "Started"), schedule.recent)
            if let next = nextMeeting {
                addMeetingSection(MeetingMenuRowView.header("Next Meeting", bold: true), [next])
            } else {
                menu.addItem(disabledItem("No upcoming meetings"))
            }
            addMeetingSection(MeetingMenuRowView.header("Coming Up", bold: false), schedule.later)
        case .notDetermined:
            menu.addItem(disabledItem("Waiting for calendar access…"))
        case .denied:
            menu.addItem(disabledItem("Calendar access denied"))
            let open = NSMenuItem(
                title: "Open Privacy Settings…", action: #selector(openPrivacySettings),
                keyEquivalent: "")
            open.target = self
            menu.addItem(open)
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(
            title: "Quit Meeting Countdown", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// A section header, then a row per meeting (see `MeetingMenuRowView`), with a Join button
    /// when the invite has a call link.
    private func addMeetingSection(_ header: NSMenuItem, _ meetings: [Meeting]) {
        guard !meetings.isEmpty else { return }
        menu.addItem(header)
        for meeting in meetings {
            menu.addItem(makeMeetingItem(meeting))
            // ⌘J joins the next meeting. A row with a custom view can't show or own a key equivalent,
            // so a hidden item carries it.
            if meeting == nextMeeting, let link = meeting.videoLink {
                let join = NSMenuItem(title: Self.joinTitle(link), action: #selector(joinFromMenu(_:)), keyEquivalent: "j")
                join.target = self
                join.representedObject = meeting
                join.isHidden = true
                join.allowsKeyEquivalentWhenHidden = true
                menu.addItem(join)
            }
        }
    }

    /// Clicking the row shows the event in Calendar. It has to do something: a disabled row draws gray,
    /// even with an explicit text color.
    private func makeMeetingItem(_ meeting: Meeting) -> NSMenuItem {
        let item = NSMenuItem(title: meeting.title, action: #selector(showInCalendar(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = meeting
        let row = MeetingMenuRowView(
            meeting: meeting,
            calendarName: meeting.calendarID.flatMap(calendar.title(ofCalendar:)),
            isNext: meeting == nextMeeting,
            joinHelp: meeting.videoLink.map { "\(Self.joinTitle($0))\(meeting == nextMeeting ? " (⌘J)" : "")" },
            onJoin: { [weak self] in self?.join(meeting) })
        item.view = row
        meetingRows.append(row)
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func joinNextMeeting() {
        if let meeting = nextMeeting { join(meeting) }
    }

    @objc private func joinFromMenu(_ sender: NSMenuItem) {
        if let meeting = sender.representedObject as? Meeting { join(meeting) }
    }

    private func join(_ meeting: Meeting) {
        guard let link = meeting.videoLink else { return }
        VideoLinkOpener.open(link, preference: settings.videoLinkPreference(forAccount: meeting.accountID))
        joinedMeetingID = meeting.id
        updateOverlay(now: Date())
    }

    @objc private func showInCalendar(_ sender: NSMenuItem) {
        if let meeting = sender.representedObject as? Meeting { CalendarService.showInCalendar(meeting) }
    }

    private static func joinTitle(_ link: VideoLink) -> String {
        "Join \(link.provider.name)"
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func openPrivacySettings() {
        CalendarService.openPrivacySettings()
    }
}

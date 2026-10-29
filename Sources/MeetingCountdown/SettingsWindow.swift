import AppKit
import MeetingCountdownCore
import Observation
import ServiceManagement
import SwiftUI

/// What the Settings window lists, read from the system each time it opens and when calendars change.
@MainActor
@Observable
final class SettingsOptions {
    var access: CalendarService.Access = .notDetermined
    var accounts: [CalendarAccount] = []
    var isChromeInstalled = false
    /// Read only once an account uses, or is picking, a Chrome profile: the read is what makes macOS ask
    /// about (and list the app under) access to other apps' data, so it shouldn't happen just by opening Settings.
    var chromeProfileList: GoogleChrome.ProfileList?
    var chromeProfiles: [ChromeProfile] { chromeProfileList?.profiles ?? [] }
    var isMeetAppInstalled = false
    /// Owned by macOS (System Settings → General → Login Items), so it's read back rather than saved here.
    var launchAtLogin: SMAppService.Status = .notRegistered
    var launchAtLoginError: String?
}

private struct SettingsView: View {
    @Bindable var settings: AppSettings
    let options: SettingsOptions
    let updates: UpdateChecker
    let openPrivacySettings: () -> Void
    let refresh: () -> Void
    let openDataAccessSettings: () -> Void
    let loadChromeProfiles: () -> Void
    let setLaunchAtLogin: (Bool) -> Void

    /// The account whose Chrome profile is being picked in the sheet.
    @State private var choosingProfileFor: CalendarAccount?

    var body: some View {
        Form {
            generalSection
            updatesSection
            switch options.access {
            case .granted:
                if options.accounts.isEmpty {
                    Section {
                        Text("No calendars found.")
                            .foregroundStyle(.secondary)
                    } header: {
                        calendarsHeader
                    }
                }
                ForEach(options.accounts) { account in
                    accountSection(account, isFirst: account.id == options.accounts.first?.id)
                }
            case .notDetermined, .denied:
                Section("Calendars") {
                    Text("Meeting Countdown can't read your calendars. Allow it under Permissions below.")
                        .foregroundStyle(.secondary)
                }
            }
            permissionsSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 320)
        .sheet(item: $choosingProfileFor) { account in
            ChromeProfileSheet(
                account: account,
                profileList: options.chromeProfileList ?? .notInstalled,
                openDataAccessSettings: openDataAccessSettings,
                recheck: loadChromeProfiles,
                initial: chromeDirectory(for: account),
                onChoose: { directory in
                    settings.videoLinkPreferences[account.id] = .chromeProfile(directory: directory)
                    choosingProfileFor = nil
                },
                onCancel: { choosingProfileFor = nil })
        }
    }

    private var generalSection: some View {
        Section {
            Toggle("Open at login", isOn: Binding(
                get: { options.launchAtLogin == .enabled || options.launchAtLogin == .requiresApproval },
                set: { setLaunchAtLogin($0) }))
        } footer: {
            if let error = options.launchAtLoginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if options.launchAtLogin == .requiresApproval {
                HStack {
                    Text("Allow Meeting Countdown in Login Items to finish turning this on.")
                    Button("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            LabeledContent("Calendars") {
                if options.access == .granted {
                    allowedLabel
                } else {
                    Button("Allow…", action: openPrivacySettings)
                }
            }
        } header: {
            Text("Permissions")
        }
    }

    /// The result of a check sits above the button in the same row, so it shows without scrolling.
    private var updatesSection: some View {
        Section {
            LabeledContent("App Version") {
                VStack(alignment: .trailing, spacing: 6) {
                    updateStatus
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(updates.currentVersion)
                            .textSelection(.enabled)
                        if case .available(let release) = updates.state {
                            Button("Open Download Page") { NSWorkspace.shared.open(release.pageURL) }
                        } else {
                            Button("Check for Updates", action: updates.check)
                                .disabled(updates.state == .checking)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking GitHub…")
            }
        case .upToDate:
            Text("You're up to date.")
        case .available(let release):
            Text("Version \(release.versionString) is available.")
        case .failed(let message):
            Text(message)
        }
    }

    private var allowedLabel: some View {
        Label("Allowed", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    }

    /// Heads the account sections. It sits in the first section's header: a section of its own would draw a box.
    private var calendarsHeader: some View {
        HStack {
            Text("Per-Calendar Settings")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Spacer()
            Button("Refresh Calendars", systemImage: "arrow.clockwise", action: refresh)
                .help("Check for added or removed calendars and accounts")
        }
    }

    private func accountSection(_ account: CalendarAccount, isFirst: Bool) -> some View {
        Section {
            Picker("Video calls", selection: linkMode(for: account)) {
                Text("Default").tag(LinkMode.defaultBrowser)
                Text("Prefer Google Meet app").tag(LinkMode.meetApp)
                Text("Prefer Chrome Profile…").tag(LinkMode.chromeProfile)
            }
            if let directory = chromeDirectory(for: account) {
                LabeledContent("Chrome profile") {
                    HStack {
                        Text(profileName(directory))
                        Button("Change…") { chooseProfile(for: account) }
                    }
                }
            }
            ForEach(account.calendars) { calendar in
                Toggle(isOn: includes(calendar.id)) {
                    Label {
                        Text(calendar.title)
                    } icon: {
                        Circle()
                            .fill(calendar.color.map(Color.init(cgColor:)) ?? .secondary)
                            .frame(width: 10, height: 10)
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 16) {
                if isFirst { calendarsHeader }
                Text(account.title)
            }
        } footer: {
            if let warning = warning(for: account) {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The picker's three choices; the Chrome profile itself is picked in a sheet.
    private enum LinkMode: Hashable {
        case defaultBrowser, meetApp, chromeProfile
    }

    private func linkMode(for account: CalendarAccount) -> Binding<LinkMode> {
        Binding(
            get: {
                switch settings.videoLinkPreference(forAccount: account.id) {
                case .defaultBrowser: .defaultBrowser
                case .meetApp: .meetApp
                case .chromeProfile: .chromeProfile
                }
            },
            set: { mode in
                switch mode {
                case .defaultBrowser: settings.videoLinkPreferences[account.id] = nil
                case .meetApp: settings.videoLinkPreferences[account.id] = .meetApp
                // Saved only once a profile is chosen; cancelling leaves the picker where it was.
                case .chromeProfile: chooseProfile(for: account)
                }
            })
    }

    /// Reads Chrome's profile list first, so the sheet opens with it (or with macOS's answer).
    private func chooseProfile(for account: CalendarAccount) {
        loadChromeProfiles()
        choosingProfileFor = account
    }

    private func chromeDirectory(for account: CalendarAccount) -> String? {
        if case .chromeProfile(let directory) = settings.videoLinkPreference(forAccount: account.id) {
            return directory
        }
        return nil
    }

    private func profileName(_ directory: String) -> String {
        switch options.chromeProfileList {
        case .found(let profiles):
            profiles.first(where: { $0.directory == directory })?.displayName ?? "\(directory) (missing)"
        // Names come from the same file as the list, so all we know is the folder.
        case .blocked, .notInstalled, nil:
            directory
        }
    }

    private func warning(for account: CalendarAccount) -> String? {
        switch settings.videoLinkPreference(forAccount: account.id) {
        case .meetApp where !options.isMeetAppInstalled:
            "The Google Meet app isn't installed, so calls open in your default browser."
        case .chromeProfile where !options.isChromeInstalled:
            "Google Chrome isn't installed, so calls open in your default browser."
        case .chromeProfile(let directory)
        where options.chromeProfileList?.isFound == true && !options.chromeProfiles.contains(where: { $0.directory == directory }):
            "This Chrome profile no longer exists, so calls open in your default browser."
        default:
            nil
        }
    }

    private func includes(_ calendarID: String) -> Binding<Bool> {
        Binding(
            get: { settings.calendarSelection.includes(calendarID) },
            set: { settings.calendarSelection.setIncluded($0, calendarID: calendarID) }
        )
    }
}

/// Picks the Chrome profile an account's calls open in.
private struct ChromeProfileSheet: View {
    let account: CalendarAccount
    let profileList: GoogleChrome.ProfileList
    let openDataAccessSettings: () -> Void
    let recheck: () -> Void
    let onChoose: (String) -> Void
    let onCancel: () -> Void

    @State private var selection: String?

    init(
        account: CalendarAccount, profileList: GoogleChrome.ProfileList, openDataAccessSettings: @escaping () -> Void,
        recheck: @escaping () -> Void, initial: String?, onChoose: @escaping (String) -> Void, onCancel: @escaping () -> Void
    ) {
        self.account = account
        self.profileList = profileList
        self.openDataAccessSettings = openDataAccessSettings
        self.recheck = recheck
        self.onChoose = onChoose
        self.onCancel = onCancel
        _selection = State(initialValue: initial ?? Self.bestMatch(for: account, in: profileList.profiles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open \(account.title) calls in which Chrome profile?")
                .font(.headline)
            switch profileList {
            case .notInstalled:
                message("Google Chrome isn't installed.")
            case .blocked:
                message("To list Chrome's profiles, macOS needs your OK for Meeting Countdown to read data from other apps. Turn on Meeting Countdown in Privacy & Security → Files & Folders; this list updates when you come back.")
                Button("Open Files & Folders Settings…", action: openDataAccessSettings)
                    // Coming back from System Settings doesn't reliably make this menu bar app active again,
                    // so keep checking while blocked; the task ends when the list loads and this view goes away.
                    .task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(1))
                            recheck()
                        }
                    }
            case .found(let profiles) where profiles.isEmpty:
                message("Chrome has no profiles yet. Open Chrome once, then try again.")
            case .found(let profiles):
                List(profiles, selection: $selection) { profile in
                    Text(profile.displayName).tag(profile.directory)
                }
                .frame(minHeight: 200)
                // The list can arrive after the sheet opens, once access is allowed in System Settings.
                .onChange(of: profiles) {
                    if selection == nil { selection = Self.bestMatch(for: account, in: profiles) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Choose") { selection.map(onChoose) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The profile signed in to the account's own Google address, if any (Google accounts are titled by their email).
    private static func bestMatch(for account: CalendarAccount, in profiles: [ChromeProfile]) -> String? {
        profiles.first(where: { $0.email?.caseInsensitiveCompare(account.title) == .orderedSame })?.directory
    }
}

/// The Settings window: which calendars to watch, and where Join opens calls.
@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let calendar: CalendarService
    private let options = SettingsOptions()
    private let updates = UpdateChecker()
    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?
    /// Set once the user starts picking a Chrome profile, so later reloads keep the list current.
    private var wantsChromeProfiles = false

    init(settings: AppSettings, calendar: CalendarService) {
        self.settings = settings
        self.calendar = calendar
        // Coming back from System Settings: pick up permissions granted there.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.window?.isVisible == true { self?.reload() }
            }
        }
    }

    func show() {
        reload()
        let window = window ?? makeWindow()
        self.window = window
        // Called from the status menu: wait for it to finish closing, since activating mid-close can leave the
        // window behind the app that was in front. Activation is only a request on macOS 14+, so also order
        // the window front regardless of whether it's granted.
        DispatchQueue.main.async {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// Re-reads calendars, Chrome profiles and installed apps; cheap enough to call on every calendar change.
    func reload() {
        options.access = calendar.access
        options.accounts = calendar.accounts()
        options.isChromeInstalled = GoogleChrome.appURL != nil
        let usesChromeProfile = options.accounts.contains {
            if case .chromeProfile = settings.videoLinkPreference(forAccount: $0.id) { true } else { false }
        }
        if usesChromeProfile || wantsChromeProfiles {
            options.chromeProfileList = GoogleChrome.profileList()
        }
        options.isMeetAppInstalled = InstalledWebApp.find(forHost: "meet.google.com") != nil
        options.launchAtLogin = SMAppService.mainApp.status
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            options.launchAtLoginError = nil
        } catch {
            NSLog("Launch at login \(enabled ? "register" : "unregister") failed: \(error)")
            options.launchAtLoginError = "Couldn't change this: \(error.localizedDescription)"
        }
        options.launchAtLogin = SMAppService.mainApp.status
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(
            settings: settings, options: options, updates: updates,
            openPrivacySettings: { CalendarService.openPrivacySettings() },
            refresh: { [weak self] in
                self?.calendar.refreshAccounts()
                self?.reload()
            },
            openDataAccessSettings: { GoogleChrome.openDataAccessSettings() },
            loadChromeProfiles: { [weak self] in
                guard let self else { return }
                wantsChromeProfiles = true
                let list = GoogleChrome.profileList()
                if list.isFound != options.chromeProfileList?.isFound {
                    NSLog("Chrome profile list: \(list.isFound ? "\(list.profiles.count) profiles" : "\(list)")")
                }
                options.chromeProfileList = list
            },
            setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Meeting Countdown Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 460, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

import AppKit
import MeetingCountdownCore

/// Opens a call: in the provider's desktop app if there is one, else where the user chose in Settings
/// (a web app installed from Chrome or another Chromium browser, or a Chrome profile), else the default browser.
@MainActor
enum VideoLinkOpener {
    static func open(_ link: VideoLink, preference: VideoLinkPreference) {
        if let appURL = link.appURL, NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            NSWorkspace.shared.open(appURL)
            return
        }
        switch preference {
        case .meetApp:
            if let webApp = InstalledWebApp.find(forHost: link.url.host), webApp.open(link.url) {
                return
            }
        case .chromeProfile(let directory):
            if GoogleChrome.open(link.url, profileDirectory: directory) {
                return
            }
        case .defaultBrowser:
            break
        }
        NSWorkspace.shared.open(link.url)
    }
}

/// Google Chrome's profiles, and opening a URL in a chosen one.
@MainActor
enum GoogleChrome {
    static let bundleID = "com.google.Chrome"

    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    enum ProfileList {
        case notInstalled
        /// macOS protects other apps' data: reading Chrome's profile list needs the user's OK in
        /// Privacy & Security → Files & Folders, and no prompt is shown.
        case blocked
        /// Empty if Chrome has never run.
        case found([ChromeProfile])

        var profiles: [ChromeProfile] {
            if case .found(let profiles) = self { profiles } else { [] }
        }
        var isFound: Bool { if case .found = self { true } else { false } }
    }

    static func profileList() -> ProfileList {
        guard appURL != nil else { return .notInstalled }
        let localState = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
        do {
            return .found(ChromeProfile.profiles(fromLocalState: try Data(contentsOf: localState)))
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .blocked
        } catch {
            return .found([])
        }
    }

    /// macOS won't let an app grant itself access, so this opens the pane where the user can.
    static func openDataAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        NSWorkspace.shared.open(url)
    }

    /// Opens `url` in a new tab of the profile's window (a new window if the profile has none open).
    /// Returns false if Chrome or the profile is gone; Chrome would quietly create a missing profile.
    /// If the profile list can't be read, the saved profile is trusted.
    static func open(_ url: URL, profileDirectory: String) -> Bool {
        guard let chrome = appURL else { return false }
        if case .found(let profiles) = profileList(), !profiles.contains(where: { $0.directory == profileDirectory }) {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        // A fresh instance hands the arguments to the running browser and exits, like `open -n --args`.
        config.createsNewApplicationInstance = true
        config.arguments = ["--profile-directory=\(profileDirectory)", url.absoluteString]
        NSWorkspace.shared.openApplication(at: chrome, configuration: config) { _, error in
            if let error {
                NSLog("Opening \(url) in Chrome profile \(profileDirectory) failed: \(error.localizedDescription)")
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
        }
        return true
    }
}

/// A site installed as an app from a Chromium browser ("Install Google Meet…"), e.g.
/// ~/Applications/Chrome Apps.localized/Google Meet.app. These register no URL scheme, and opening the
/// app bundle with a URL ignores the URL, so we ask the browser itself to show the URL in the app.
struct InstalledWebApp {
    let bundleURL: URL
    let id: String
    let startHost: String
    let browserBundleID: String

    /// Chromium browsers put their app shims in ~/Applications/<Browser> Apps.localized/.
    static func find(forHost host: String?) -> InstalledWebApp? {
        guard let host = host?.lowercased() else { return nil }
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.lastPathComponent.hasSuffix("Apps.localized") {
            let apps = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                if let webApp = InstalledWebApp(bundle: app), webApp.startHost == host {
                    return webApp
                }
            }
        }
        return nil
    }

    init?(bundle: URL) {
        guard let info = Bundle(url: bundle)?.infoDictionary,
            let id = info["CrAppModeShortcutID"] as? String,
            let start = (info["CrAppModeShortcutURL"] as? String).flatMap(URL.init(string:)),
            let host = start.host?.lowercased(),
            let browser = info["CrBundleIdentifier"] as? String
        else { return nil }
        self.bundleURL = bundle
        self.id = id
        self.startHost = host
        self.browserBundleID = browser
    }

    /// Returns false if the browser that installed the app can't be found.
    func open(_ url: URL) -> Bool {
        guard let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID) else {
            return false
        }
        // Scripting the browser can block (on its first use macOS asks for permission), so keep it off the main thread.
        Task.detached { [self] in
            let reused = showInOpenWindow(url)
            await MainActor.run {
                if reused {
                    bringToFront()
                } else {
                    launch(url, browser: browser)
                }
            }
        }
        return true
    }

    /// Loads the call in a window of this app that's already open, if one is free; see `WebAppWindowChooser`.
    /// Fails (returning false) if the browser isn't running, has no such window, or we may not script it.
    private func showInOpenWindow(_ url: URL) -> Bool {
        // The bundle ID is spliced into the scripts: AppleScript needs it literally to know the browser's terms.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browserBundleID).isEmpty,
            browserBundleID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return false }

        // Web app windows have a single tab, so ordinary browser windows are never touched.
        let listing = Self.runAppleScript("""
            tell application id "\(browserBundleID)"
                set out to ""
                repeat with w in windows
                    if (count of tabs of w) is 1 then set out to out & (id of w) & (character id 9) & (URL of active tab of w) & linefeed
                end repeat
                return out
            end tell
            """)
        guard let listing else { return false }
        let windows = listing.split(separator: "\n").compactMap { line -> (id: Int, url: URL)? in
            let fields = line.split(separator: "\t", maxSplits: 1)
            guard fields.count == 2, let id = Int(fields[0]), let url = URL(string: String(fields[1])) else { return nil }
            return (id, url)
        }

        let (windowID, newURL): (Int, String)
        switch WebAppWindowChooser.choose(for: url, windows: windows) {
        case .focus(let id): (windowID, newURL) = (id, "")
        case .navigate(let id): (windowID, newURL) = (id, url.absoluteString)
        case nil: return false
        }
        return Self.runAppleScript("""
            on run argv
                tell application id "\(browserBundleID)"
                    set w to window id ((item 1 of argv) as integer)
                    if (item 2 of argv) is not "" then set URL of active tab of w to (item 2 of argv)
                    set index of w to 1
                end tell
            end run
            """, arguments: [String(windowID), newURL]) != nil
    }

    private func bringToFront() {
        // Opening the app's shim while it runs just activates it, with the window we raised on top.
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func launch(_ url: URL, browser: URL) {
        let config = NSWorkspace.OpenConfiguration()
        // A fresh instance hands the arguments to the running browser and exits, like `open -n --args`.
        config.createsNewApplicationInstance = true
        config.arguments = ["--app-id=\(id)", "--app-launch-url-for-shortcuts-menu-item=\(url.absoluteString)"]
        NSWorkspace.shared.openApplication(at: browser, configuration: config) { _, error in
            if let error {
                NSLog("Opening \(url) in web app \(id) failed: \(error.localizedDescription)")
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
        }
    }

    /// Runs AppleScript through osascript, so a slow or blocked script can't stall the app. Nil on failure.
    private static func runAppleScript(_ source: String, arguments: [String] = []) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            NSLog("AppleScript failed: \(message)")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

# Meeting Countdown: notes for Claude

Product plan: [intent.md](intent.md). Build, run, test and code layout: [README.md](README.md).
This file records decisions and things learned the hard way that aren't obvious from the code.

## Working in this repo

- Keep logic that can be tested without AppKit/EventKit in `MeetingCountdownCore`, with XCTest coverage; the app target only wires it to the system.
- Use `scripts/dev.sh` to rebuild and relaunch.
- Signing: `build-app.sh` signs with `SIGN_IDENTITY` (an Apple Development cert, picked by SHA-1). Its designated requirement names the cert, not the binary, so TCC grants survive rebuilds. A revoked cert still shows up in the keychain, under the same name as its replacement. Signing with one makes amfid reject the app, and Gatekeeper moves it to the Trash as malware. Check a cert with `openssl ocsp` before switching to it.
- To inspect real calendar data, a terminal process is refused calendar access. Wrap a probe in a small ad-hoc-signed `.app` with `NSCalendarsFullAccessUsageDescription`, and launch it with `open -W` so macOS can ask.

## Video call links (Join)

**Where links live.** EventKit has no conference field: Google's structured conference data isn't exposed. Detection scans `EKEvent.url`, then `location`, then `notes`, and takes the first call link it finds (`VideoLinkDetector`).
- Google Meet links sit inside Google's `-::~:~::~:` block in `notes`.
- `url` held only `message:` / `sms://` links that Calendar.app adds, never a call.
- Zoom/Teams invites often put the link in `location`.
- Only links that join a call count. Dial-in pages (`tel.meet`), help pages and downloads are ignored. Add a test when changing these rules.
- Detection runs only on the meetings the menu lists (`MeetingSelector.schedule`: started in the last 30 min, the next one, and the rest in the next 90 min), not on every event in the week.

**Opening a link** (`VideoLinkOpener`), in this order:
1. Native app via `VideoLink.appURL` (`zoommtg://` for Zoom `/j/<id>`, `msteams:` for Teams `/l/` links), only if some app handles that scheme.
2. A web app installed from a Chromium browser (see below).
3. The default browser.

**Chrome-installed web apps** (`InstalledWebApp`). Google Meet has no native Mac app; people often install it as a Chrome web app: `~/Applications/Chrome Apps.localized/Google Meet.app`.
- Its `Info.plist` has `CrAppModeShortcutID`, `CrAppModeShortcutURL` (start URL; matched by host) and `CrBundleIdentifier` (the browser). Edge and Canary use the same keys in their own `* Apps.localized` folders.
- Opening the shim with a URL (`open -a "Google Meet.app" <url>`) ignores the URL.
- Launching the browser with `--app-id=<id> --app-launch-url-for-shortcuts-menu-item=<url>` (as a new instance, like `open -na`) works, but always opens a new window.

**Settings: where calls open, per account.** Each calendar account (EventKit source; Google accounts are titled by their email) picks Default (default browser), Prefer Google Meet app, or Prefer Chrome Profile. Zoom/Teams desktop apps still win in every mode.
- Chrome lists profiles in `~/Library/Application Support/Google/Chrome/Local State` (`profile.info_cache`: folder → `name`, `user_name`; `profiles_order`). macOS protects it as another app's data. Reading it fails with `fileReadNoPermission` (EPERM): no prompt appears, only a "Data Access Blocked" notice pointing to Privacy & Security → Files & Folders (confirmed with a probe app, Oct 2026). Apps can't grant themselves this, and there's no API to request it: the denied read itself is what makes macOS list the app there. So Settings only reads the file once the user picks "Prefer Chrome Profile…" (or an account already uses it), never just on opening Settings. When blocked, the profile sheet links to that pane (`GoogleChrome.ProfileList.blocked`) and re-checks when the app becomes active again. While blocked, Join trusts the saved profile folder.
- The TCC service is `kTCCServiceSystemPolicyAppDataDetailed` ("does not allow prompting"). The grant is tied to the code requirement. With ad-hoc signing (`SIGN_IDENTITY=-`) that changes on every build: macOS logs "Failed to match existing code requirement" and records denied again. Fix: `tccutil reset SystemPolicyAppDataDetailed com.rtortora.MeetingCountdown`, read once with the new build, then toggle. `/usr/bin/log show --predicate 'subsystem == "com.apple.TCC"'` shows these lines (plain `log` is a zsh builtin).
- Open a URL in a profile by launching Chrome as a new instance with `--profile-directory=<folder> <url>`. Chrome silently creates a profile that doesn't exist, so check the folder is still listed first.

**Reusing an open web app window.**
- How: Chrome's AppleScript lists windows; web app windows have exactly one tab. Set `URL of active tab` on the chosen window, raise it, then open the shim bundle to activate it.
- Which window: `WebAppWindowChooser`. It focuses a window already in this call, or reuses one on the site that isn't in a call. It must never navigate a window that's in another call, which would drop the user from it.
- Scripts run through `/usr/bin/osascript` in a child process off the main thread. The first-run Automation prompt blocks until answered, and macOS attributes it to Meeting Countdown (`NSAppleEventsUsageDescription` in Info.plist). If denied or failed, fall back to launching a new window.
- AppleScript gotchas:
  - Inside `tell application "Google Chrome"`, `tab` means Chrome's tab class, not a tab character. Use `(character id 9)`.
  - The browser's bundle ID must be literal in the script, not a variable, or its terms (`tabs`, `active tab`) don't compile. Validate it before splicing it in.

**Overlay UI.**
- The overlay's hosting view takes every mouse-down to drag the panel, so a SwiftUI `Button` never receives clicks. The Join button is an `NSButton` (via `NSViewRepresentable`) with `acceptsFirstMouse` returning true; as its own subview it receives the click.
- After Join, the overlay stays hidden for that meeting (`joinedMeetingID`) so it doesn't cover the call when it glides to center. This is intended.

## Menu

- A disabled `NSMenuItem` draws gray even with an explicit `foregroundColor` in its `attributedTitle` (tried Oct 2026). So the next-meeting row is enabled: clicking it shows the event in Calendar.app via `ical://ekevent/<calendarItemIdentifier>?method=show&options=more`, which Apple doesn't document.
- The menu lists meetings under "Started" (last 30 min), "Next Meeting" (shown however far off) and "Coming Up" (next 90 min), each with its own Join item; only the next meeting's has ⌘J. Items carry their `Meeting` in `representedObject`.
- The rows' badges ("in 12 min", "5 min ago") are updated in place on each tick, because rebuilding the menu waits until it closes.

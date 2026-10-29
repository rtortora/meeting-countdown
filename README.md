# Meeting Countdown

A macOS menu bar app that watches your calendars (via EventKit) and shows a live countdown overlay in the 10 minutes before your next meeting. See [intent.md](intent.md) for the product plan.

Requires macOS 14+ and Xcode / Swift 6.

## Build & run

```sh
scripts/build-app.sh          # builds build/MeetingCountdown.app (release)
open build/MeetingCountdown.app
```

While developing, `scripts/dev.sh` does both in one step: it builds (debug by default; pass `release` for a release build), quits any running instance, and launches the new build.

On first launch macOS asks for calendar access. If you deny it, the menu bar item offers a shortcut to the Calendars privacy pane.

Note: the bundle is signed with an Apple Development certificate (`SIGN_IDENTITY` in `scripts/build-app.sh`; set `SIGN_IDENTITY=-` to sign ad-hoc), so permissions carry over between rebuilds. To reset the calendar permission, run `tccutil reset Calendar com.rtortora.MeetingCountdown`.

## Tests

```sh
swift test
```

## Layout

- `Sources/MeetingCountdownCore` contains the pure logic: picking the next meeting, the countdown/overlay-window math, and finding video call links in invites (`VideoLink`). It has no EventKit dependency and is unit tested.
- `Sources/MeetingCountdown` is the app: the EventKit wrapper (`CalendarService`), the floating panel (`OverlayController`), the menu bar item plus tick loop (`AppController`), and opening a call in a native app, a browser-installed web app, or the browser (`VideoLinkOpener`).
- `Resources/Info.plist` sets `LSUIElement` (so there is no Dock icon), the calendar usage strings, and the Apple Events usage string (Join scripts the browser to reuse an open web app window).
- `Resources/AppIcon.png` is the app icon; `scripts/build-app.sh` turns it into `AppIcon.icns`.

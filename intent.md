Meeting Countdown is a small MacOS app that lives in the Mac menu bar that can connect your calendars, watch for meetings, and provides a live count-down at 10 minutes down to the next meeting. There is a small dismiss action, and a primary action that, based on the calendar invite details, tries to open the appropriate video chat app to directly connect.

Calendars are read through Apple's EventKit, so any calendars the user already has configured on their Mac (via Calendar.app or System Settings → Internet Accounts, e.g. iCloud, Google, Exchange/Microsoft 365, CalDAV) work out of the box with zero extra configuration beyond granting calendar access. Optional custom configuration may be layered on top of this (e.g. choosing which calendars to watch, or adding sources EventKit can't see), but it should never be required to get started.

## Phase 1: End-to-end calendar vertical slice

Goal: prove the full path from the user's existing Mac calendars to a live on-screen countdown, with the smallest amount of app around it.

In scope:
- A menu bar app (no Dock icon) that requests calendar access via EventKit on first launch.
- Reads events from all calendars the user has configured, and finds the next upcoming meeting (skip all-day events and events the user has declined).
- Shows a live countdown overlay on screen to that meeting: a small, always-on-top floating window showing the meeting title and time remaining, ticking every second.
- The overlay appears when the next meeting is within 10 minutes and disappears once the meeting starts.
- Reacts to calendar changes (new, moved, or cancelled events) without restarting the app.
- The menu bar item shows the next meeting's title and start time, plus a Quit option.
- If calendar access is denied, the menu bar item says so and offers a way to open the relevant System Settings pane.

Out of scope for Phase 1:
- Detecting or opening video chat links / apps.
- Dismiss action and any other overlay interactions.
- Custom configuration (calendar selection, extra sources, adjustable lead time).
- Notifications, sounds, launch at login, polish of visuals.

Done when: with a test event created in Calendar.app a few minutes in the future, the overlay appears, counts down live to the start time, and goes away at the start time. Moving or deleting that event in Calendar.app updates the overlay accordingly.

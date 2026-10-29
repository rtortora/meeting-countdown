#!/usr/bin/env bash
# Rebuilds the app, quits any running instance, and launches the fresh build.
# Usage: scripts/dev.sh [debug|release] [app args...]   (defaults to debug for faster builds)
# e.g. scripts/dev.sh debug --demo   shows a made-up schedule instead of your calendars.
set -euo pipefail

CONFIG="${1:-debug}"
shift || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MeetingCountdown.app"
BUNDLE_ID="com.rtortora.MeetingCountdown"

# Build first so a failed build leaves the running instance alone.
"$ROOT/scripts/build-app.sh" "$CONFIG"

if pgrep -x MeetingCountdown >/dev/null; then
    echo "Quitting running instance..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x MeetingCountdown >/dev/null || break
        sleep 0.25
    done
    if pgrep -x MeetingCountdown >/dev/null; then
        echo "Still running; killing it."
        pkill -x MeetingCountdown || true
        sleep 0.5
    fi
fi

if [ $# -gt 0 ]; then
    open "$APP" --args "$@"
else
    open "$APP"
fi
echo "Launched $APP"

#!/usr/bin/env bash
# Builds MeetingCountdown and wraps it in a .app bundle (needed for the Info.plist
# calendar usage string and LSUIElement). Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MeetingCountdown.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MeetingCountdown" "$APP/Contents/MacOS/MeetingCountdown"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# App icon: resize Resources/AppIcon.png into an iconset, then pack it as AppIcon.icns.
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Sign with the Apple Development cert, so TCC grants (calendar, Automation, Chrome's
# Local State) survive rebuilds: its designated requirement names the cert, not the
# binary's hash. Picked by SHA-1 because a revoked cert in the keychain has the same name.
# Override with SIGN_IDENTITY=<sha1>; without a usable identity, fall back to ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:-E536D5B8C773D13F0A6BE1AA361EC211127C3349}"
if [ "$SIGN_IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "warning: signing identity $SIGN_IDENTITY not found; signing ad-hoc" >&2
    SIGN_IDENTITY="-"
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"

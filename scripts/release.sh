#!/usr/bin/env bash
# Builds, tests and publishes a GitHub Release (a .dmg) from this machine.
# Usage: scripts/release.sh <version>    e.g. scripts/release.sh 0.2.0
# Signs with the keychain's "Developer ID Application" identity (override with DEVELOPER_ID)
# and notarizes with the notarytool keychain profile NOTARY_PROFILE (default
# meeting-countdown; create it once with `xcrun notarytool store-credentials meeting-countdown`).
# Without a Developer ID identity the app is ad-hoc signed, and Gatekeeper blocks it until
# the user allows it in Privacy & Security.
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MeetingCountdown.app"
ZIP="$ROOT/build/MeetingCountdown-notarize.zip"
DMG="$ROOT/build/MeetingCountdown-$VERSION.dmg"
STAGING="$ROOT/build/dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-meeting-countdown}"

cd "$ROOT"
if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree has uncommitted changes" >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "error: tag $TAG already exists" >&2
    exit 1
fi

DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning \
    | { grep 'Developer ID Application' || true; } | head -1 | awk '{print $2}')}"
if [ -z "$DEVELOPER_ID" ]; then
    echo "warning: no Developer ID Application identity; the release will be ad-hoc signed" >&2
fi

swift test
ARCHS="arm64 x86_64" VERSION="$VERSION" SIGN_IDENTITY=- scripts/build-app.sh release

if [ -n "$DEVELOPER_ID" ]; then
    # The hardened runtime (required for notarization) needs the entitlements file.
    codesign --force --options runtime --timestamp \
        --entitlements "$ROOT/Resources/MeetingCountdown.entitlements" \
        --sign "$DEVELOPER_ID" "$APP"
    # Notarize the app itself (notarytool takes a zip) and staple the ticket, so the copy
    # dragged out of the disk image opens offline too.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --wait --keychain-profile "$NOTARY_PROFILE"
    rm -f "$ZIP"
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

# Disk image: the app next to an Applications shortcut to drag it onto.
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/MeetingCountdown.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Meeting Countdown" -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGING"
if [ -n "$DEVELOPER_ID" ]; then
    codesign --timestamp --sign "$DEVELOPER_ID" "$DMG"
    xcrun notarytool submit "$DMG" --wait --keychain-profile "$NOTARY_PROFILE"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --title "Meeting Countdown $VERSION" --generate-notes
echo "Released $TAG"

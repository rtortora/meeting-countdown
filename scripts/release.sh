#!/usr/bin/env bash
# Builds, tests and publishes a GitHub Release (a .dmg) from this machine.
# Usage: scripts/release.sh [--minor | --major | <version>]
# Without arguments, bumps the patch number of the newest vX.Y.Z tag (0.1.0 -> 0.1.1);
# --minor and --major bump those instead (-> 0.2.0, -> 1.0.0). Asks before publishing.
# Signs with the keychain's "Developer ID Application" identity (override with DEVELOPER_ID)
# and notarizes with the notarytool keychain profile NOTARY_PROFILE (default
# meeting-countdown; create it once with `xcrun notarytool store-credentials meeting-countdown`).
# Without a Developer ID identity the app is ad-hoc signed, and Gatekeeper blocks it until
# the user allows it in Privacy & Security.
# Release notes are drafted by the Codex CLI (`brew bundle` installs it from the Brewfile;
# then `codex login` with ChatGPT) and opened in $VISUAL/$EDITOR for editing; set EDITOR="code --wait" for VS Code.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

git fetch -q --tags origin
LATEST="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)"
IFS=. read -r MAJOR MINOR PATCH <<<"${LATEST#v}"
MAJOR="${MAJOR:-0}" MINOR="${MINOR:-0}" PATCH="${PATCH:-0}"
case "${1:-}" in
    "") VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    --minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    --major) VERSION="$((MAJOR + 1)).0.0" ;;
    [0-9]*.[0-9]*.[0-9]*) VERSION="$1" ;;
    *) echo "usage: release.sh [--minor | --major | <version>]" >&2; exit 1 ;;
esac
TAG="v$VERSION"
APP="$ROOT/build/MeetingCountdown.app"
ZIP="$ROOT/build/MeetingCountdown-notarize.zip"
DMG="$ROOT/build/MeetingCountdown-$VERSION.dmg"
STAGING="$ROOT/build/dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-meeting-countdown}"

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

read -r -p "Release $TAG (latest: ${LATEST:-none})? [y/N] " REPLY
[[ "$REPLY" =~ ^[Yy] ]] || exit 1

# Release notes: Codex (signed in with ChatGPT) drafts them from the changes since the last
# tag, then they open in $VISUAL/$EDITOR for review. A draft left over from an earlier run
# that failed later on is reused, edits included.
NOTES="$ROOT/build/release-notes-$TAG.md"
mkdir -p "$ROOT/build"
if [ ! -s "$NOTES" ]; then
    BASE="${LATEST:-$(git hash-object -t tree /dev/null)}"
    if command -v codex >/dev/null; then
        {
            git log --no-merges --format='- %s%n%b' ${LATEST:+"$LATEST..HEAD"}
            echo
            git diff "$BASE" HEAD -- . ':(exclude)Tests' ':(exclude)*.png'
        } | codex exec --ephemeral -o "$NOTES" \
            "Write release notes for Meeting Countdown $VERSION, a macOS menu bar app that counts \
down to your next meeting. Below are the commit messages and diff since ${LATEST:-the start}. \
Write for end users, not developers: a few short Markdown bullets about what they will notice \
(new features, changes, fixes), most important first. Leave out refactors, tests, build and \
release tooling. No heading, no intro or closing sentence. Output only the notes." \
            >/dev/null || echo "warning: codex failed; starting from the commit list" >&2
    else
        echo "warning: codex not found (brew bundle; codex login); starting from the commit list" >&2
    fi
    [ -s "$NOTES" ] || git log --no-merges --format='- %s' ${LATEST:+"$LATEST..HEAD"} >"$NOTES"
fi
${VISUAL:-${EDITOR:-vi}} "$NOTES"
if [ ! -s "$NOTES" ]; then
    echo "error: release notes are empty" >&2
    exit 1
fi
echo "--- Release notes ---"
cat "$NOTES"
echo "---"
read -r -p "Use these notes? [y/N] " REPLY
[[ "$REPLY" =~ ^[Yy] ]] || exit 1

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
gh release create "$TAG" "$DMG" --title "Meeting Countdown $VERSION" --notes-file "$NOTES"
rm -f "$NOTES"
echo "Released $TAG"

#!/bin/zsh
# One command from a downloaded TFT XAPK/zip to an auto-updating Mactician.
#
# Usage:
#   update-game-from-apk.command <bundle.zip|.xapk|.apks|dir> [--build] [--publish] [--skip-tests]
#
# Without flags it only imports and verifies the game (private APKs, release
# manifest, version bump, notes). --build also validates and builds the DMG.
# --publish also uploads the DMG to the `updates` GitHub release and commits the
# signed appcast to the Pages branch, which is what installed copies of Mactician
# poll; they then offer the update, and the new bundled game installs on launch.
# Publishing is an outward-facing action, so it asks for confirmation first.
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
typeset bundle="" ; typeset -i BUILD=0 PUBLISH=0 SKIP_TESTS=0
for argument in "$@"; do
    case "$argument" in
        --build) BUILD=1 ;;
        --publish) PUBLISH=1; BUILD=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
        -*) print -u2 "Unknown option: $argument"; exit 2 ;;
        *) [[ -z "$bundle" ]] || { print -u2 "Only one bundle may be given."; exit 2; }; bundle="$argument" ;;
    esac
done
[[ -n "$bundle" ]] || { print -u2 "Usage: ${0:t} <bundle> [--build] [--publish] [--skip-tests]"; exit 2; }
[[ -e "$bundle" ]] || { print -u2 "Not found: $bundle"; exit 2; }
cd "$PROJECT_DIR"

# --- 1. Import, verify, and prepare the release ---------------------------
python3 -I scripts/ingest-game-apk.py "$bundle"
(( BUILD == 1 )) || { print "Imported. Re-run with --build (and --publish) to ship it."; exit 0; }

# --- 2. Validate and build -------------------------------------------------
export TFT_ANDROID_NDK="${TFT_ANDROID_NDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/ndk/27.3.13750724}"
[[ -d "$TFT_ANDROID_NDK" ]] || { print -u2 "Android NDK r27d not found; set TFT_ANDROID_NDK."; exit 2; }
export TFT_GAME_APK_DIR="${TFT_GAME_APK_DIR:-$PROJECT_DIR/private/tft-apks}"

./scripts/verify-repository.command
(( SKIP_TESTS == 1 )) || ./scripts/test-mactician.command
./scripts/build-mactician.command

readonly VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' launcher/Info.plist)"
readonly DMG="$PROJECT_DIR/dist/Mactician-$VERSION.dmg"
[[ -f "$DMG" ]] || { print -u2 "Expected DMG was not produced: $DMG"; exit 1; }
print "Built $DMG"
(( PUBLISH == 1 )) || { print "Built. Re-run with --publish (or see docs/releasing.md) to upload."; exit 0; }

# --- 3. Publish (outward-facing: confirm) ----------------------------------
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || { print -u2 "gh is not authenticated."; exit 2; }
export MACTICIAN_SPARKLE_ACCOUNT="${MACTICIAN_SPARKLE_ACCOUNT:-mactician-launcher-updates}"
if [[ -z "${MACTICIAN_UPDATE_PAGES_BRANCH:-}" ]]; then
    typeset repo
    repo="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
    MACTICIAN_UPDATE_PAGES_BRANCH="$(gh api "repos/$repo/pages" --jq '.source.branch' 2>/dev/null || true)"
    export MACTICIAN_UPDATE_PAGES_BRANCH="${MACTICIAN_UPDATE_PAGES_BRANCH:-gh-pages}"
fi

print "\nAbout to publish Mactician $VERSION:"
print "  - upload $DMG (and deltas) to the 'updates' GitHub release (immutable)"
print "  - commit the signed appcast.xml to branch '$MACTICIAN_UPDATE_PAGES_BRANCH'"
print "  The DMG bundles Riot's unmodified game APKs; installed copies update to it."
read -q "?Continue? [y/N] " || { print "\nStopped before publishing."; exit 1; }
print
./scripts/publish-mactician-update.command --allow-adhoc
print "Published Mactician $VERSION. Installed copies will offer it on their next check."

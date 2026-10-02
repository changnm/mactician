#!/bin/zsh
# Fetches the newest TFT build for one edition and, if it is newer than the live
# signed feed, hands it to publish-game-update.command (which verifies the Riot
# certificate, package, version, and split set before signing anything).
#
# Usage: auto-publish-game-update.command [--check-feed-only]
#
# Publishing is opt-in: unless MACTICIAN_AUTO_PUBLISH=1 the release is only
# prepared and signed locally (--prepare-only) and nothing is uploaded.
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly EDITION="${MACTICIAN_GAME_EDITION:-global}"
readonly UPDATE_BASE_URL="${MACTICIAN_UPDATE_BASE_URL:-https://sergeinaumov.dev/mactician/updates}"
readonly BUILD_TOOLS="${MACTICIAN_ANDROID_BUILD_TOOLS:-}"
readonly AUTO_PUBLISH="${MACTICIAN_AUTO_PUBLISH:-0}"
readonly FETCH_SCRIPT="${MACTICIAN_APK_FETCH_SCRIPT:-}"
readonly WORK_ROOT="${MACTICIAN_AUTO_UPDATE_WORKDIR:-$PROJECT_DIR/dist/auto-game-update-$EDITION}"
typeset -i CHECK_FEED_ONLY=0

for argument in "$@"; do
    case "$argument" in
        --check-feed-only) CHECK_FEED_ONLY=1 ;;
        *) print -u2 "Usage: ${0:t} [--check-feed-only]"; exit 2 ;;
    esac
done

case "$EDITION" in
    global)  readonly PACKAGE="com.riotgames.league.teamfighttactics"; readonly GAME_PATH="game" ;;
    vietnam) readonly PACKAGE="com.riotgames.league.teamfighttacticsvn"; readonly GAME_PATH="game/vietnam" ;;
    taiwan)  readonly PACKAGE="com.riotgames.league.teamfighttacticstw"; readonly GAME_PATH="game/taiwan" ;;
    *) print -u2 "MACTICIAN_GAME_EDITION must be global, vietnam, or taiwan."; exit 2 ;;
esac
readonly FEED_URL="$UPDATE_BASE_URL/$GAME_PATH/manifest.json"
[[ "$UPDATE_BASE_URL" == https://* ]] || { print -u2 "MACTICIAN_UPDATE_BASE_URL must be an https URL."; exit 2; }
[[ "$AUTO_PUBLISH" == (0|1) ]] || { print -u2 "MACTICIAN_AUTO_PUBLISH must be 0 or 1."; exit 2; }

for tool in curl jq openssl unzip; do
    command -v "$tool" >/dev/null || { print -u2 "$tool is required."; exit 1; }
done

case "$WORK_ROOT" in
    "/"|"/Users"|"$HOME"|"$PROJECT_DIR")
        print -u2 "Refusing unsafe work directory: $WORK_ROOT"
        exit 2
        ;;
esac
rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT"

report() {
    # Emit a result for GitHub Actions (when present) and the terminal.
    local outcome="$1" message="$2"
    print "[$EDITION] $message"
    [[ -z "${GITHUB_OUTPUT:-}" ]] || print "outcome=$outcome" >>"$GITHUB_OUTPUT"
    [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || print "- **$EDITION**: $message" >>"$GITHUB_STEP_SUMMARY"
}

# The version code of the signed feed that users currently receive. A missing
# feed (404) means this edition was never published; any other failure aborts so
# a network blip can never look like "nothing published yet".
live_version_code() {
    local body="$WORK_ROOT/live-feed.json" http_status code
    http_status="$(curl --silent --location --proto '=https' --max-time 30 \
        --output "$body" --write-out '%{http_code}' "$FEED_URL" || true)"
    case "$http_status" in
        200)
            code="$(jq -er '.payload' "$body" | openssl base64 -d -A | jq -er '.release.versionCode')" \
                || { print -u2 "The live feed at $FEED_URL could not be decoded."; return 1; }
            [[ "$code" == <1-> ]] || { print -u2 "The live feed has an invalid version code."; return 1; }
            print -r -- "$code"
            ;;
        404) print 0 ;;
        *) print -u2 "Could not read the live feed ($FEED_URL): HTTP $http_status"; return 1 ;;
    esac
}

readonly LIVE_VERSION_CODE="$(live_version_code)"
if (( CHECK_FEED_ONLY == 1 )); then
    print "$LIVE_VERSION_CODE"
    exit 0
fi

[[ -x "$BUILD_TOOLS/aapt" && -x "$BUILD_TOOLS/apksigner" ]] || {
    print -u2 "MACTICIAN_ANDROID_BUILD_TOOLS must contain official aapt and apksigner tools."
    exit 2
}

readonly DOWNLOAD_DIR="$WORK_ROOT/download"
readonly EXTRACT_DIR="$WORK_ROOT/extract"
readonly STAGE_DIR="$WORK_ROOT/stage"
mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR" "$STAGE_DIR"

# --- 1. Fetch the newest build --------------------------------------------
if [[ -n "$FETCH_SCRIPT" ]]; then
    [[ -x "$FETCH_SCRIPT" ]] || { print -u2 "MACTICIAN_APK_FETCH_SCRIPT is not executable."; exit 2; }
    "$FETCH_SCRIPT" "$PACKAGE" "$DOWNLOAD_DIR"
else
    command -v apkeep >/dev/null || { print -u2 "apkeep is required (brew install apkeep)."; exit 1; }
    apkeep --app "$PACKAGE" --download-source apk-pure "$DOWNLOAD_DIR"
fi

typeset bundle
for bundle in "$DOWNLOAD_DIR"/**/*.(xapk|apks)(N.); do
    unzip -q -o "$bundle" -d "$EXTRACT_DIR/${bundle:t:r}"
done

# --- 2. Normalize into the exact four-file layout the publisher expects ----
typeset apk name base_candidate=""
typeset -a other_candidates
for apk in "$DOWNLOAD_DIR"/**/*.apk(N.) "$EXTRACT_DIR"/**/*.apk(N.); do
    name="${apk:t}"
    name="${name#split_}"
    case "$name" in
        config.arm64_v8a.apk|config.en.apk|config.mdpi.apk)
            cp -f "$apk" "$STAGE_DIR/$name"
            ;;
        config.*.apk)
            ;;
        "$PACKAGE.apk"|base.apk)
            base_candidate="$apk"
            ;;
        *)
            other_candidates+=("$apk")
            ;;
    esac
done
if [[ -z "$base_candidate" && ${#other_candidates[@]} -eq 1 ]]; then
    base_candidate="${other_candidates[1]}"
fi
[[ -n "$base_candidate" ]] || {
    print -u2 "Could not identify the base APK. Candidates: ${other_candidates[*]:-none}"
    exit 1
}
cp -f "$base_candidate" "$STAGE_DIR/base.apk"

typeset required
for required in base.apk config.arm64_v8a.apk config.en.apk config.mdpi.apk; do
    [[ -f "$STAGE_DIR/$required" ]] || {
        print -u2 "The downloaded build is missing $required. Found: $(ls "$STAGE_DIR" | tr '\n' ' ')"
        exit 1
    }
done

# --- 3. Decide whether it is newer than the live feed ----------------------
readonly BADGING="$("$BUILD_TOOLS/aapt" dump badging "$STAGE_DIR/base.apk")"
readonly VERSION_CODE="$(print -r -- "$BADGING" \
    | sed -n "s/^package:.* versionCode='\([0-9][0-9]*\)'.*/\1/p" | head -n 1)"
readonly VERSION_NAME="$(print -r -- "$BADGING" \
    | sed -n "s/^package:.* versionName='\([^']*\)'.*/\1/p" | head -n 1)"
[[ "$VERSION_CODE" == <1-> ]] || { print -u2 "Could not read the version code from the APK."; exit 1; }
[[ "$VERSION_NAME" =~ '^[0-9]+(\.[0-9]+)+-[0-9]+$' ]] || {
    print -u2 "Unexpected version name: $VERSION_NAME"
    exit 1
}
[[ -z "${GITHUB_OUTPUT:-}" ]] || {
    print "version=$VERSION_NAME" >>"$GITHUB_OUTPUT"
    print "version_code=$VERSION_CODE" >>"$GITHUB_OUTPUT"
}

if (( VERSION_CODE <= LIVE_VERSION_CODE )); then
    report current "$VERSION_NAME (code $VERSION_CODE) is not newer than the live feed (code $LIVE_VERSION_CODE); nothing to do."
    exit 0
fi

# --- 4. Verify, sign, and (optionally) publish -----------------------------
typeset -a publish_flags
(( AUTO_PUBLISH == 1 )) || publish_flags=(--prepare-only)
MACTICIAN_GAME_APK_DIR="$STAGE_DIR" \
MACTICIAN_GAME_EDITION="$EDITION" \
MACTICIAN_GAME_VERSION="$VERSION_NAME" \
MACTICIAN_GAME_VERSION_CODE="$VERSION_CODE" \
MACTICIAN_ANDROID_BUILD_TOOLS="$BUILD_TOOLS" \
    "$PROJECT_DIR/scripts/publish-game-update.command" "${publish_flags[@]}"

if (( AUTO_PUBLISH == 1 )); then
    report published "Published $VERSION_NAME (code $VERSION_CODE), previously code $LIVE_VERSION_CODE."
else
    report prepared "Prepared and signed $VERSION_NAME (code $VERSION_CODE) without uploading; set MACTICIAN_AUTO_PUBLISH=1 to publish."
fi

#!/bin/zsh
# Prepares and publishes a Sparkle update for the launcher.
#
# Update archives (the DMG and its deltas) are release assets of one fixed
# GitHub release, and the signed appcast is a file on the GitHub Pages branch.
# The app polls SUFeedURL from its Info.plist, which must be the appcast URL
# computed here. Nothing is uploaded unless --prepare-only is absent.
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"

typeset -i PREPARE_ONLY=0
typeset -i ALLOW_ADHOC=0
usage() {
    print -u2 "Usage: ${0:t} [--prepare-only] [--allow-adhoc]"
}
for argument in "$@"; do
    case "$argument" in
        --prepare-only)
            (( PREPARE_ONLY == 0 )) || { usage; exit 2; }
            PREPARE_ONLY=1
            ;;
        --allow-adhoc)
            (( ALLOW_ADHOC == 0 )) || { usage; exit 2; }
            ALLOW_ADHOC=1
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

readonly SPARKLE_ROOT="$("$PROJECT_DIR/scripts/prepare-sparkle.command")"
readonly GENERATE_APPCAST="$SPARKLE_ROOT/bin/generate_appcast"
readonly GENERATE_KEYS="$SPARKLE_ROOT/bin/generate_keys"
readonly SPARKLE_ACCOUNT="${MACTICIAN_SPARKLE_ACCOUNT:-}"

# "owner/name" of the GitHub repository that hosts the update archives.
derive_repository() {
    local url
    url="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$url" =~ 'github\.com[:/]([^/]+)/([^/]+)$' ]] || return 0
    print -r -- "${match[1]}/${match[2]%.git}"
}
readonly UPDATE_REPO="${MACTICIAN_UPDATE_REPO:-$(derive_repository)}"
readonly RELEASE_TAG="${MACTICIAN_UPDATE_RELEASE_TAG:-updates}"
readonly PAGES_BRANCH="${MACTICIAN_UPDATE_PAGES_BRANCH:-gh-pages}"
readonly APP="${MACTICIAN_APP:-$PROJECT_DIR/dist/Mactician.app}"
readonly UPDATE_ROOT="${MACTICIAN_UPDATE_WORKDIR:-$PROJECT_DIR/dist/mactician-updates}"

if [[ -z "$SPARKLE_ACCOUNT" ]]; then
    print -u2 "MACTICIAN_SPARKLE_ACCOUNT must name the Sparkle Ed25519 key stored in Keychain."
    exit 2
fi
if [[ ! "$UPDATE_REPO" =~ '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' ]]; then
    print -u2 "Set MACTICIAN_UPDATE_REPO to the GitHub repository as owner/name."
    exit 2
fi
if [[ ! "$RELEASE_TAG" =~ '^[A-Za-z0-9._-]+$' ]] || [[ "$PAGES_BRANCH" == @* ]] || ! git check-ref-format --branch "$PAGES_BRANCH" >/dev/null 2>&1; then
    print -u2 "MACTICIAN_UPDATE_RELEASE_TAG must be a plain name and MACTICIAN_UPDATE_PAGES_BRANCH a valid branch name."
    exit 2
fi

# The appcast is served by GitHub Pages; the archives are release downloads.
readonly APPCAST_URL="${MACTICIAN_APPCAST_URL:-https://${(L)UPDATE_REPO%%/*}.github.io/${UPDATE_REPO##*/}/appcast.xml}"
readonly DOWNLOAD_PREFIX="https://github.com/$UPDATE_REPO/releases/download/$RELEASE_TAG/"
readonly PRODUCT_URL="${MACTICIAN_UPDATE_PRODUCT_URL:-https://github.com/$UPDATE_REPO}"
readonly PAGES_REMOTE="${MACTICIAN_UPDATE_PAGES_REMOTE:-https://github.com/$UPDATE_REPO.git}"
[[ "$APPCAST_URL" == https://* ]] || { print -u2 "MACTICIAN_APPCAST_URL must be an https URL."; exit 2; }

if [[ ! -d "$APP" ]]; then
    print -u2 "Build Mactician before preparing an update."
    exit 1
fi

readonly INFO_PLIST="$APP/Contents/Info.plist"
readonly VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
readonly BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
readonly BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
readonly PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw "$INFO_PLIST")"
readonly FEED_URL="$(plutil -extract SUFeedURL raw "$INFO_PLIST")"
readonly DMG="${MACTICIAN_DMG:-$PROJECT_DIR/dist/Mactician-$VERSION.dmg}"
readonly RELEASE_BASENAME="Mactician-$VERSION"
readonly RELEASE_ARCHIVE="$UPDATE_ROOT/$RELEASE_BASENAME.dmg"
readonly RELEASE_NOTES_SOURCE="${MACTICIAN_RELEASE_NOTES:-$PROJECT_DIR/launcher/Resources/release-notes/$VERSION.md}"
readonly RELEASE_NOTES="$UPDATE_ROOT/$RELEASE_BASENAME.md"
readonly APPCAST="$UPDATE_ROOT/appcast.xml"

if [[ ! -f "$DMG" ]]; then
    print -u2 "Mactician DMG not found: $DMG"
    exit 1
fi

if [[ "$BUNDLE_ID" != "dev.sergeinaumov.mactician" ]]; then
    print -u2 "Unexpected launcher bundle identifier: $BUNDLE_ID"
    exit 1
fi
# The app must verify updates with the key that signs them, and must poll the
# appcast this script publishes; otherwise installed copies could never update.
readonly KEYCHAIN_PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null || true)"
if [[ -z "$KEYCHAIN_PUBLIC_KEY" || "$PUBLIC_KEY" != "$KEYCHAIN_PUBLIC_KEY" ]]; then
    print -u2 "The launcher's SUPublicEDKey does not match the public key of Keychain account '$SPARKLE_ACCOUNT'."
    exit 1
fi
if [[ "$FEED_URL" != "$APPCAST_URL" ]]; then
    print -u2 "The launcher's SUFeedURL ($FEED_URL) is not the appcast this script publishes ($APPCAST_URL)."
    exit 1
fi
if [[ ! -f "$RELEASE_NOTES_SOURCE" ]]; then
    print -u2 "Release notes not found: $RELEASE_NOTES_SOURCE"
    exit 1
fi

if (( PREPARE_ONLY == 0 )); then
    readonly CODESIGN_DETAILS="$(codesign -dvv "$APP" 2>&1)"
    if [[ "$CODESIGN_DETAILS" == *'Authority=Developer ID Application:'* ]]; then
        codesign --verify --deep --strict "$APP"
        xcrun stapler validate "$DMG"
        spctl --assess --type open --context context:primary-signature "$DMG"
    elif (( ALLOW_ADHOC == 1 )); then
        if [[ "$CODESIGN_DETAILS" != *'Signature=adhoc'* ]]; then
            print -u2 "The temporary release must contain a valid ad-hoc app signature."
            exit 1
        fi
        codesign --verify --deep --strict "$APP"
        hdiutil verify "$DMG" >/dev/null
        print -u2 "Warning: publishing an ad-hoc build without Apple notarization."
    else
        print -u2 "Publishing requires a Developer ID-signed launcher build."
        print -u2 "Use --allow-adhoc only for an explicitly approved temporary release."
        exit 1
    fi
fi

mkdir -p "$UPDATE_ROOT"
ditto "$DMG" "$RELEASE_ARCHIVE"
ditto "$RELEASE_NOTES_SOURCE" "$RELEASE_NOTES"

# Release notes are embedded in the appcast, so only the archives are uploaded.
"$GENERATE_APPCAST" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --embed-release-notes \
    --link "$PRODUCT_URL" \
    --maximum-versions 3 \
    --maximum-deltas 5 \
    "$UPDATE_ROOT"

MACTICIAN_RELEASE_TITLE="Mactician $VERSION" \
    perl -0pi -e '
        s{(<channel>.*?<title>).*?(</title>)}{$1Mactician Updates$2}s;
        s{(<item>.*?<title>).*?(</title>)}{$1$ENV{MACTICIAN_RELEASE_TITLE}$2}s;
    ' "$APPCAST"

xmllint --noout "$APPCAST"
if ! grep -Fq '<title>Mactician Updates</title>' "$APPCAST" \
        || ! grep -Fq "<title>Mactician $VERSION</title>" "$APPCAST"; then
    print -u2 "Generated appcast titles do not match the Mactician release metadata."
    exit 1
fi
if ! grep -Fq 'sparkle:edSignature=' "$APPCAST"; then
    print -u2 "Generated appcast does not contain an Ed25519 archive signature."
    exit 1
fi
if ! grep -Fq "url=\"${DOWNLOAD_PREFIX}${RELEASE_BASENAME}.dmg\"" "$APPCAST"; then
    print -u2 "Generated appcast does not point at ${DOWNLOAD_PREFIX}${RELEASE_BASENAME}.dmg."
    exit 1
fi

if (( PREPARE_ONLY == 1 )); then
    print "Prepared Sparkle feed with signed update archives: $APPCAST"
    exit 0
fi

command -v gh >/dev/null || { print -u2 "The GitHub CLI (gh) is required to upload update archives."; exit 1; }
command -v git >/dev/null || { print -u2 "git is required to publish the appcast."; exit 1; }

# Assets already on the release, as "name<TAB>size<TAB>digest" lines.
typeset existing
if ! existing="$(gh api "repos/$UPDATE_REPO/releases/tags/$RELEASE_TAG" \
        --jq '.assets[] | [.name, (.size | tostring), (.digest // "")] | @tsv' 2>/dev/null)"; then
    print -u2 "The '$RELEASE_TAG' release does not exist in $UPDATE_REPO. Create it once, then rerun:"
    print -u2 "  gh release create $RELEASE_TAG --repo $UPDATE_REPO --prerelease --title 'Mactician update archives' \\"
    print -u2 "    --notes 'Archives referenced by the Mactician appcast. Do not edit or delete.'"
    exit 1
fi

# Upload only this release's artifacts and never overwrite: a published archive
# must keep its bytes, because the appcast signs them. An archive that is already
# there with identical content is skipped, so an interrupted publish can be rerun.
typeset -a RELEASE_FILES UPLOAD_FILES
typeset release_file asset_line asset_name asset_size asset_digest local_sha
typeset -i identical
RELEASE_FILES=("$RELEASE_ARCHIVE")
for release_file in "$UPDATE_ROOT"/Mactician"$BUILD"-*.delta(.N); do
    RELEASE_FILES+=("$release_file")
done
for release_file in "${RELEASE_FILES[@]}"; do
    asset_name="${release_file:t}"
    asset_line="$(print -r -- "$existing" | awk -F'\t' -v name="$asset_name" '$1 == name')"
    if [[ -z "$asset_line" ]]; then
        UPLOAD_FILES+=("$release_file")
        continue
    fi
    asset_size="$(print -r -- "$asset_line" | cut -f2)"
    asset_digest="$(print -r -- "$asset_line" | cut -f3)"
    if [[ -n "$asset_digest" ]]; then
        local_sha="sha256:$(shasum -a 256 "$release_file" | awk '{print $1}')"
        [[ "$asset_digest" == "$local_sha" ]] && identical=1 || identical=0
    else
        [[ "$asset_size" == "$(stat -f '%z' "$release_file")" ]] && identical=1 || identical=0
    fi
    if (( identical == 0 )); then
        print -u2 "$asset_name already exists on the '$RELEASE_TAG' release with different content."
        print -u2 "Published archives are immutable; increase the build number instead of replacing it."
        exit 1
    fi
    print "Already uploaded with identical content: $asset_name"
done
if (( ${#UPLOAD_FILES[@]} > 0 )); then
    gh release upload "$RELEASE_TAG" --repo "$UPDATE_REPO" "${UPLOAD_FILES[@]}"
fi

# Publish the appcast last, on the Pages branch, so no client sees an entry
# whose archive is not yet downloadable.
readonly PAGES_WORK="$(mktemp -d)"
trap 'rm -rf "$PAGES_WORK"' EXIT
readonly SITE="$PAGES_WORK/site"
typeset -i branch_status=0
git ls-remote --exit-code --heads "$PAGES_REMOTE" "$PAGES_BRANCH" >/dev/null 2>&1 || branch_status=$?
case "$branch_status" in
    0)
        git clone --quiet --depth 1 --branch "$PAGES_BRANCH" "$PAGES_REMOTE" "$SITE"
        ;;
    2)
        git init --quiet "$SITE"
        git -C "$SITE" checkout --quiet --orphan "$PAGES_BRANCH"
        git -C "$SITE" remote add origin "$PAGES_REMOTE"
        ;;
    *)
        print -u2 "Could not reach $PAGES_REMOTE to publish the appcast."
        exit 1
        ;;
esac
ditto "$APPCAST" "$SITE/appcast.xml"
: >"$SITE/.nojekyll"
git -C "$SITE" add appcast.xml .nojekyll
if git -C "$SITE" diff --cached --quiet; then
    print "The published appcast is already current."
else
    git -C "$SITE" commit --quiet -m "Mactician $VERSION (build $BUILD) appcast"
    git -C "$SITE" push --quiet origin "$PAGES_BRANCH"
fi

print "Published Mactician $VERSION (build $BUILD). Appcast: $APPCAST_URL"
print "GitHub Pages can take a minute or two to serve the new appcast."

# Releasing

The current metadata is Mactician version 1.3.1, build 56. Version and build
numbers live in `launcher/Info.plist` and the matching emulator-host plist.
Release notes live under `launcher/Resources/release-notes/` using the short
version as the filename.

## Release identity

Do not casually change:

- app bundle ID `dev.sergeinaumov.mactician`;
- game-host bundle ID `dev.sergeinaumov.mactician.game-host`;
- app name and executable `Mactician`;
- Application Support and DMG volume name `Mactician`;
- Sparkle feed `https://sergeinaumov.dev/mactician/updates/appcast.xml`;
- pinned Sparkle Ed25519 public key in `launcher/Info.plist`;
- UserDefaults domain and Keychain service `dev.sergeinaumov.mactician`;
- Android package ID, release-manifest hashes, or the `Android_Codex` device
  profile identifier.

These are the only current product identifiers. No old feed, local-data path,
redirect, alias, or compatibility wrapper is part of the release.

The launcher Sparkle private key is stored in the macOS login Keychain as a
generic-password item with service `https://sparkle-project.org` and account
`tft-pbe-launcher`. This locator is not secret. Its public key must be
`77t8YuvP4mvvP/3oMpVR/TqGRMCcUlrpWFIZGcWqokY=`, matching `SUPublicEDKey` in
`launcher/Info.plist`. Do not confuse it with the separate game-update keys.

## Prepare metadata

1. Update `CFBundleShortVersionString` and monotonically increase
   `CFBundleVersion` in both plist files.
2. Add matching Markdown release notes.
3. Update the `Unreleased` section in `CHANGELOG.md`.
4. Update the release manifest only when a pinned Android/game input changes;
   verify size, origin, and hash independently.
5. Run the full fast validation and review `git diff --check`.

## Build the public artifact

```sh
./scripts/build-mactician-release.command
```

The release wrapper uses the pinned APK directory, automatically selects the
installed Developer ID Application identity, enables hardened runtime and
secure timestamps, submits the DMG for Apple notarization, staples both the DMG
and app tickets, and runs the final Gatekeeper checks. No production upload
occurs in this step. Use `build-mactician.command` directly only for a local
ad-hoc validation build.

Keep the notarization profile, Developer ID private key, Apple credentials, and
Sparkle private Ed25519 key in Keychain. Never pass secret values as committed
arguments or defaults.

## Generate the appcast

Exercise generation without upload:

```sh
export MACTICIAN_SPARKLE_ACCOUNT="${MACTICIAN_SPARKLE_ACCOUNT:-tft-pbe-launcher}"
./scripts/publish-mactician-update.command --prepare-only
```

This copies the DMG and release notes to versioned names, generates Ed25519
enclosure signatures and deltas, validates XML, and requires an `edSignature`.
Prepare-only never uploads files.

## Publish

Production-specific destinations have no secret or machine-specific defaults:

```sh
export MACTICIAN_SPARKLE_ACCOUNT="${MACTICIAN_SPARKLE_ACCOUNT:-tft-pbe-launcher}"
: "${MACTICIAN_UPDATE_SSH_TARGET:?Set MACTICIAN_UPDATE_SSH_TARGET in the environment}"
: "${MACTICIAN_UPDATE_SSH_PORT:?Set MACTICIAN_UPDATE_SSH_PORT in the environment}"
: "${MACTICIAN_UPDATE_REMOTE_ROOT:?Set MACTICIAN_UPDATE_REMOTE_ROOT in the environment}"
./scripts/publish-mactician-update.command
```

Optional public settings are `MACTICIAN_UPDATE_BASE_URL`,
`MACTICIAN_UPDATE_PRODUCT_URL`, `MACTICIAN_UPDATE_WORKDIR`, `MACTICIAN_APP`,
`MACTICIAN_DMG`, and `MACTICIAN_RELEASE_NOTES`.

The publisher verifies the Developer ID app and stapled DMG, uploads immutable
artifacts for the current version and its deltas, uploads the next appcast under
a temporary name, then atomically moves the appcast into place last. Older
release files remain untouched on the server. Never overwrite a published
versioned DMG with different bytes.

`--allow-adhoc` is reserved for an explicitly approved temporary release. It
accepts only a valid ad-hoc-signed app, verifies the DMG, and still requires the
Sparkle Ed25519 signature.

## Publish on GitHub Releases (forks and ad-hoc builds)

The upstream [v1.3.0 release](https://github.com/tweet9ra/mactician/releases/tag/v1.3.0)
is a tag named `v1.3.0`, titled "Mactician 1.3.0", with one asset
(`Mactician-1.3.0.dmg`, Developer ID signed and notarized) and notes ending in
the DMG's SHA-256. A fork can publish the same shape without the upstream server,
Sparkle key, or Apple account. Nothing below uploads automatically; creating a
tag or release is a separate external action.

1. **Choose a new version.** Do not reuse 1.3.0 (build 55): upstream already
   shipped different bytes under it. Raise `CFBundleShortVersionString` and
   `CFBundleVersion` in both `launcher/Info.plist` and
   `launcher/Resources/EmulatorHost-Info.plist`, add
   `launcher/Resources/release-notes/<version>.md`, and move the `Unreleased`
   changelog entries under the new version. `verify-repository.command` also
   requires the same version and build in the README `Version:` line, the first
   line of `CHANGELOG.md`, and the first line of this guide.
2. **Validate.** Run `./scripts/test-mactician.command` and the manual checks in
   [Validation and rollback](#validation-and-rollback).
3. **Build the DMG** from the commit you will tag.
   - *Ad hoc, no Apple account:* the commands in
     [Local ad-hoc build](../README.md#local-ad-hoc-build). Other Macs must use
     **Open Anyway**, so mark the release as a pre-release.
   - *Developer ID, as upstream:* needs an Apple Developer Program membership, a
     Developer ID Application certificate and a `notarytool` Keychain profile
     (`mactician-notary` by default), then `./scripts/build-mactician-release.command`.
4. **Decide how the app updates.** `SUFeedURL` and `SUPublicEDKey` in
   `launcher/Info.plist` are upstream's. A fork build checks upstream's appcast
   every 24 hours and is offered any upstream build with a higher
   `CFBundleVersion`, which would replace the fork build (including its bundled
   game). Either accept that, or run your own channel: generate your own Sparkle
   Ed25519 key, host an appcast, and change `SUFeedURL`/`SUPublicEDKey` together
   with their pinned copies in `launcher/Tests/LauncherTests.swift`,
   `scripts/publish-mactician-update.command`, and the docs. The signed game
   feed (`MacticianIdentity.gameUpdateURL`) is read-only for the app and can stay
   upstream's, because a newer bundled game is installed without it.
5. **Write the notes.** The notes file ends with the DMG hash, which changes with
   every build, so regenerate that section:

   ```sh
   VERSION=1.3.1   # the version you chose
   DMG="dist/Mactician-$VERSION.dmg"
   SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
   {
     sed '/^## Verify the download/,$d' "launcher/Resources/release-notes/$VERSION.md"
     printf '## Verify the download\n\n`%s` SHA-256:\n\n`%s`\n' "$(basename "$DMG")" "$SHA"
   } > "$TMPDIR/notes-$VERSION.md"
   ```

6. **Tag and create the release.** `gh auth login` is interactive and is done
   by you once; never put tokens in commands or files. Start with `--draft` to
   review the page before it is public, and add `--prerelease` for ad-hoc builds:

   ```sh
   git tag -a "v$VERSION" -m "Mactician $VERSION"
   git push origin "v$VERSION"
   gh release create "v$VERSION" "$DMG" --repo OWNER/mactician \
     --title "Mactician $VERSION" --notes-file "$TMPDIR/notes-$VERSION.md" --draft
   ```

   Publish the draft from the web page after checking the asset size and notes.
7. **Check the published asset.** Download it on another Mac and compare its
   SHA-256 with the notes before announcing it.

The DMG contains Riot's unmodified game APKs (Global, and Vietnam when listed in
`editionGames`). Upstream ships Global this way; publishing a DMG that also
carries Vietnam redistributes that package too. Decide whether that is acceptable
before making a release public: a draft, or a build kept for personal use, does
not distribute anything.

## Publish a TFT game update

See [Vietnam edition inputs and validation](vietnam.md) for the VNG channel and
[Taiwan edition inputs and validation](taiwan.md) for the Taiwan channel.

Game releases use a separate signed manifest and do not require a new Mactician
build. Put the complete official split APK set in one directory and run:

```sh
: "${MACTICIAN_GAME_APK_DIR:?Set the split APK directory}"
: "${MACTICIAN_GAME_VERSION:?Set the Android version name}"
: "${MACTICIAN_GAME_VERSION_CODE:?Set the Android version code}"
: "${MACTICIAN_ANDROID_BUILD_TOOLS:?Directory containing official aapt and apksigner}"
export MACTICIAN_GAME_EDITION=global # or vietnam or taiwan
./scripts/publish-game-update.command --prepare-only
```

The publisher verifies the pinned Riot certificate, package, version code,
and the base / ARM64 / English / mdpi split set before signing. The supplied
version must match the APK metadata. Use separate private APK directories for
each package. The default output directory includes the edition name.

Review the generated payload and APK hashes. To publish, set
`MACTICIAN_UPDATE_SSH_TARGET` and `MACTICIAN_UPDATE_REMOTE_ROOT`, then rerun
without `--prepare-only`. `MACTICIAN_GAME_SIGNING_ACCOUNT` defaults to the
dedicated `mactician-game-updates` Keychain account.

The publisher uploads immutable APK files before atomically replacing the
signed `game/manifest.json` (Global), `game/vietnam/manifest.json` (VNG), or
`game/taiwan/manifest.json` (Taiwan).
Publish each regional feed before distributing a launcher that offers that edition.
Never publish an incomplete split set, reuse a
release URL for different bytes, or roll the version code backwards.

## Automate TFT game updates

`.github/workflows/publish-game-update.yml` runs every six hours (and on demand)
for Global, Vietnam, and Taiwan. For each edition,
`scripts/auto-publish-game-update.command` downloads the newest build, rebuilds
the exact four-file split set, and compares its version code with the live signed
feed. Only a strictly newer build continues, and it passes through the same
`publish-game-update.command` checks as a manual release: pinned Riot
certificate, package name, version metadata, and split set. Installed launchers
then offer the update within 30 minutes.

One-time setup for a fork:

1. Replace the feed key and host in `launcher/Sources/CoreModels.swift` with your
   own, then ship that launcher build.
2. Create an environment named `game-feed` and add these secrets:
   `GAME_FEED_SIGNING_KEY` (the exported Sparkle Ed25519 private key),
   `GAME_FEED_SSH_KEY` (a deploy key limited to the update directory), and
   `GAME_FEED_SSH_KNOWN_HOSTS` (the output of `ssh-keyscan -p PORT HOST`).
3. Add these repository variables: `GAME_FEED_ENABLED=true`,
   `MACTICIAN_UPDATE_BASE_URL`, `MACTICIAN_UPDATE_SSH_TARGET`,
   `MACTICIAN_UPDATE_REMOTE_ROOT`, and optionally `MACTICIAN_UPDATE_SSH_PORT`.
4. Run the workflow manually with `publish` off and read the job summary. Scheduled
   runs only prepare and sign until you also set `GAME_FEED_AUTOPUBLISH=true`.

The default download source is APKPure through `apkeep`. To use another source,
point `MACTICIAN_APK_FETCH_SCRIPT` at an executable that receives the package name
and an output directory and leaves the APK files or an XAPK there. Check that
source's terms before automating downloads. Scheduled workflows are paused by
GitHub after 60 days without repository activity, and a job fails visibly when the
download is missing a required split, so watch for failed runs. New game builds can
change rendering behavior; the performance patches stay limited to builds listed in
the changelog.

## Make the repository public

The canonical repository is `https://github.com/tweet9ra/mactician`. Before
changing its visibility, run `./scripts/verify-repository.command`, the complete
test suite, and the secret/history scan on the exact commit that will become
public. Confirm that the repository contains no ignored build inputs, release
artifacts, credentials, signing material, or local experiment output.

Apply the description, homepage, topics, and social preview recorded in
`.github/repository-metadata.yml`. Enable Issues and GitHub Private Vulnerability
Reporting, then verify the public Source, Issues, Security, and Releases pages in
a signed-out browser. Protect the default branch against force pushes once the
initial public commit is final.

Create an immutable `v1.0.0` tag and GitHub release only after the corresponding
DMG and release notes are final. Publish the SHA-256 shown on the product page
with the release, upload the self-hosted Sparkle files, and publish the appcast
last. Repository settings, visibility changes, tags, releases, and uploads are
separate external actions.

## Validation and rollback

Before announcing a release, install the DMG on another supported Mac, verify
Gatekeeper assessment, install/update flow, Sparkle signature verification,
runtime-state preservation, first launch, Repair, stop/rollback, and a manual
update check.

If a release is defective, stop advertising it or publish a higher, fixed
version. Do not reuse a version/build number or rotate the Ed25519 key as an
incident shortcut. A compromised private key requires an explicit security
response.

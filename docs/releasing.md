# Releasing

The current metadata is Mactician version 1.3.2, build 57. Version and build
numbers live in `launcher/Info.plist` and the matching emulator-host plist.
Release notes live under `launcher/Resources/release-notes/` using the short
version as the filename.

## Release identity

Do not casually change:

- app bundle ID `dev.sergeinaumov.mactician`;
- game-host bundle ID `dev.sergeinaumov.mactician.game-host`;
- app name and executable `Mactician`;
- Application Support and DMG volume name `Mactician`;
- Sparkle feed `https://changnm.github.io/mactician/appcast.xml`;
- pinned Sparkle Ed25519 public key in `launcher/Info.plist`;
- UserDefaults domain and Keychain service `dev.sergeinaumov.mactician`;
- Android package ID, release-manifest hashes, or the `Android_Codex` device
  profile identifier.

These are the only current product identifiers. No old feed, local-data path,
redirect, alias, or compatibility wrapper is part of the release.

The launcher Sparkle private key is stored in the macOS login Keychain as a
generic-password item with service `https://sparkle-project.org` and account
`mactician-launcher-updates`. This locator is not secret. Its public key must be
`eBbmAXoj411ac+FvqD4NNxQZ56HZO9LvIW+mdo1zmfY=`, matching `SUPublicEDKey` in
`launcher/Info.plist`; `publish-mactician-update.command` refuses to run if the
app's key differs from the Keychain key. Print it with
`launcher/.build/sparkle-2.9.4/bin/generate_keys --account mactician-launcher-updates -p`
and back the private key up outside the repository with `-x <file>`. Losing it
means no installed launcher can accept an update again. Do not confuse it with
the separate game-update key (`mactician-game-updates`).

This is the fork's own channel. Builds made before it existed (for example the
first 1.3.1 draft DMG) carry upstream's feed and key, so they never see these
updates; users of those builds install a build with this channel by hand once.

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

## Update channel on GitHub

Launcher updates need no server of your own. The signed appcast is a file on the
GitHub Pages branch, and the archives are assets of one fixed release:

| What | Where |
| --- | --- |
| `appcast.xml` | `https://<owner>.github.io/<repo>/appcast.xml`, from the `gh-pages` branch (this is `SUFeedURL`) |
| DMG and `.delta` archives | `https://github.com/<owner>/<repo>/releases/download/updates/` |

The archives live in a single release tagged `updates`, separate from the
user-facing `v<version>` releases, because the appcast applies one download
prefix to every entry. Release notes are embedded in the appcast.

One-time setup:

```sh
gh release create updates --prerelease --title 'Mactician update archives' \
  --notes 'Archives referenced by the Mactician appcast. Do not edit or delete.'
```

Then publish once with the script below, and in the repository settings under
Pages choose "Deploy from a branch", the same branch, and `/ (root)`. The branch
is `gh-pages` by default, which keeps generated files out of the source history.

Any branch can be the Pages source. To serve from another one, for example while
developing on a feature branch, set `MACTICIAN_UPDATE_PAGES_BRANCH` to it
(`feature/add-for-update` is valid) and choose that branch under Pages. The
publisher then adds one commit containing only `appcast.xml` and `.nojekyll` to
that branch. Pull before pushing your own work, and note that the whole branch
becomes the site. If the branch is merged and deleted, the appcast URL stops
working and installed launchers can no longer see updates, so move to a
dedicated branch before that.

## Generate the appcast

Exercise generation without upload:

```sh
export MACTICIAN_SPARKLE_ACCOUNT=mactician-launcher-updates
./scripts/publish-mactician-update.command --prepare-only
```

This copies the DMG and release notes to versioned names, generates Ed25519
enclosure signatures and deltas, validates XML, and requires an `edSignature`
and the expected download URL. It also requires that the app's `SUPublicEDKey`
equals the Keychain account's public key and that its `SUFeedURL` equals the
appcast URL it would publish. Prepare-only never uploads files. Keep the work
directory (`dist/mactician-updates` by default) between releases: Sparkle builds
deltas from the older archives it finds there.

## Publish

```sh
export MACTICIAN_SPARKLE_ACCOUNT=mactician-launcher-updates
gh auth status
./scripts/publish-mactician-update.command            # Developer ID build
./scripts/publish-mactician-update.command --allow-adhoc   # ad-hoc build
```

The repository defaults to the `origin` remote. Optional settings are
`MACTICIAN_UPDATE_REPO` (`owner/name`), `MACTICIAN_UPDATE_RELEASE_TAG`,
`MACTICIAN_UPDATE_PAGES_BRANCH`, `MACTICIAN_APPCAST_URL` (for a custom Pages
domain; it must equal the app's `SUFeedURL`), `MACTICIAN_UPDATE_PRODUCT_URL`,
`MACTICIAN_UPDATE_WORKDIR`, `MACTICIAN_APP`, `MACTICIAN_DMG`, and
`MACTICIAN_RELEASE_NOTES`.

The publisher verifies the Developer ID app and stapled DMG, uploads the current
version's DMG and its deltas to the `updates` release without overwriting
anything, then commits the appcast to the Pages branch last, so no client sees
an entry whose archive is not yet downloadable. Never replace a published
archive with different bytes: the appcast signs them.

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
4. **Updates.** The app polls this fork's appcast on GitHub Pages and verifies
   it with the fork's own Sparkle key, so it is never offered upstream's builds.
   After the DMG is final, publish the update as described in
   [Update channel on GitHub](#update-channel-on-github). The signed game feed
   (`MacticianIdentity.gameUpdateURL`) is separate: it can stay upstream's,
   because a newer bundled game is installed without it. To publish your own
   patches instead, see [Run your own game feed](#run-your-own-game-feed).
5. **Write the notes.** The notes file ends with the DMG hash, which changes with
   every build, so regenerate that section:

   ```sh
   VERSION=1.3.2   # the version you chose
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
with the release, upload the update archives, and publish the appcast last
(see [Update channel on GitHub](#update-channel-on-github)). Repository settings, visibility changes, tags, releases, and uploads are
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

## Run your own game feed

A build trusts exactly one game-feed host and one Ed25519 public key, both
compiled in (`MacticianIdentity.gameUpdateURL` and
`MacticianIdentity.gameUpdatePublicKeyBase64` in
`launcher/Sources/CoreModels.swift`). Out of the box these are upstream's, so a
fork only ever sees patches that upstream publishes. To publish your own, create
a key, host the feed, and switch the two constants.

1. **Create the signing key.** It is stored in the login Keychain and never
   written to the repository:

   ```sh
   launcher/.build/sparkle-2.9.4/bin/generate_keys --account mactician-game-updates
   launcher/.build/sparkle-2.9.4/bin/generate_keys --account mactician-game-updates -p   # print the public key again
   ```

   Back the private key up outside the repository
   (`generate_keys --account mactician-game-updates -x <file>`). The public key
   is compiled into every launcher, so losing the private key means no installed
   launcher can accept a feed again until users install a rebuilt one. This is
   the key `publish-game-update.command` signs with by default; it is separate
   from the Sparkle app-update key.
2. **Host the feed.** Static files on one HTTPS host, served directly on port 443
   with no query strings, at exactly the paths the app validates:

   ```text
   /mactician/updates/game/manifest.json                          (Global)
   /mactician/updates/game/vietnam/manifest.json
   /mactician/updates/game/taiwan/manifest.json
   /mactician/updates/game[/<edition>]/releases/<baseSHA256>/<split>.apk
   ```

   Serve `manifest.json` with `Cache-Control: no-cache` and the APKs under
   `releases/` as immutable. The publisher uploads with `ssh`/`scp`; another
   store such as S3 or R2 behind your own domain needs a different upload step.
   Hosts that cap files at 100 MB (GitHub Pages and repositories) cannot hold
   `base.apk`, and GitHub Releases URLs redirect to another host, which the app
   rejects. The feed publishes Riot's unmodified APKs, which is the same
   redistribution decision described under
   [Publish on GitHub Releases](#publish-on-github-releases-forks-and-ad-hoc-builds).
3. **Switch the constants.** Set the host in `gameUpdateURL` and the public key in
   `gameUpdatePublicKeyBase64`. `GameEdition.updateURL`, the APK URL validation,
   and the tests derive from them. Leave the `/mactician/updates` path alone; the
   per-edition paths above and the development feed depend on it. Update the
   appcast host only if you also run your own Sparkle channel.
4. **Point the publisher at it.** The game-feed scripts default to upstream's
   URL, so always set it:

   ```sh
   export MACTICIAN_UPDATE_BASE_URL="https://updates.example.com/mactician/updates"
   ```

   Then follow [Publish a TFT game update](#publish-a-tft-game-update), or enable
   the scheduled workflow with the repository variables listed in
   `.github/workflows/publish-game-update.yml`.
5. **Roll out in this order.** Publish the feed first, then distribute a launcher
   built with the new host and key. Launchers that still carry the old key never
   read your feed, so publishing early is harmless, while a new launcher that
   starts before the feed exists reports a failed game update check. A launcher
   with the new key rejects upstream's feed, and an older launcher cannot verify
   yours. A feed cached from the old channel is ignored on the next start, and
   the launcher falls back to its bundled or installed game.

Test the switch before shipping it. `scripts/test-mactician.command` passes with
a different host and key in those two constants, and a feed signed with the
Keychain key verifies with CryptoKit and fails against upstream's key. Exercise
the full download and install against a local folder with the development feed
(`MACTICIAN_EXTRA_SWIFT_FLAGS`, see [Building](building.md)); never distribute
that build.

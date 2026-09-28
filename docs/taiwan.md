# Taiwan edition

Taiwan Mobile publishes a separate Android application,
[`com.riotgames.league.teamfighttacticstw`](https://play.google.com/store/apps/details?id=com.riotgames.league.teamfighttacticstw).
Select Taiwan alongside Global and Vietnam (VNG) on the launch screen. The
launcher remembers the selection and downloads the regional game on first use.
Game language remains an independent setting.

All three packages coexist in the shared `Tft.avd` with separate sign-ins, game
data, caches, and updates. Switching is disabled during installation and gameplay.
Reset removes every edition and the shared Android runtime.

## Verified release input

Prepared on 2026-09-10 from the APKPure `18.2-5450971` ARM64 XAPK
([source](https://apkpure.net/teamfight-tactics-league-of-l/com.riotgames.league.teamfighttacticstw/download)).
Android manifest metadata confirms version code `8450971`.
Official Android Build Tools 36 verified the cryptographic signatures, package
IDs, split IDs, and matching version codes of all four APKs. All use the pinned
Riot certificate SHA-256:

```text
931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c
```

| APK | Bytes | SHA-256 |
| --- | ---: | --- |
| base.apk | 101622071 | bd0b6b436e369c9edaf96c4ac311b809c90036b5b8ba8c1064418cf923b88abf |
| config.arm64_v8a.apk | 94106849 | 810a80b9dc2adc3f5714e2740c927d38de82adc0c5fad028ae40f6ddfbe8be90 |
| config.en.apk | 37273 | cf6ac0c92b8c32ff32ba927240733e64271394952ee8616104f4b0197f1de671 |
| config.mdpi.apk | 83007 | 5ba288e8338ed9bcf42fa7414427952ff76ef9789b04aeb5c6e5a4191162ccb7 |

## Update channel

Taiwan uses `/mactician/updates/game/taiwan/manifest.json` and immutable APK URLs
under `/mactician/updates/game/taiwan/releases/<baseSHA256>/`. It uses the pinned
game-update signing key and has no bundled Global fallback. A verified cached
feed supports offline repair.

Store the four official APK inputs in the ignored `private/tft-taiwan-apks/`
directory. The package, versions, splits, and Riot certificate must pass
`scripts/verify-game-apks.py --edition taiwan` before signing. Prepare the feed
with `MACTICIAN_GAME_EDITION=taiwan`; see [the release procedure](releasing.md).

The website nginx configuration must serve both the Taiwan manifest and APK
paths. Publish the verified feed before distributing a launcher with Taiwan.
Preparing code or a local feed alone does not make the game downloadable.

## Initial validation (TFT 18.1)

Automated tests cover saved selection, schema 1 migration, all three schema 2
game records, cross-edition feed and APK URL rejection, downgrade rejection,
separate cache and overlay paths, and package-specific runtime lifecycle polling.

The ad-hoc launcher build passed the full Swift tests and typecheck. Repository
validation passed on a clean source copy (the working folder contains Finder
metadata). The signed Taiwan feed was verified with `HostedGameUpdate.decodeAndVerify`
and matched every tested APK size and hash.

The production installer added Taiwan to a copy of an existing Global/Vietnam
AVD and preserved both existing installation records. The normal runtime then
reached Unreal `GameActivity`, remained alive for more than 25 seconds, and
showed Taiwan Mobile's content-download prompt in the selected English language
with an empty crash log. The first game launch requests approximately 3.7 GB of
additional content; this is separate from the launcher's APK download.

The Taiwan channel was published on 2026-09-08. The public manifest passed the
launcher's signature verification; all four public APK downloads matched the
tested sizes and SHA-256 hashes, with immutable cache headers. The existing
Global feed, Vietnam feed, and Sparkle appcast were unchanged. No new launcher
release was published; using Taiwan requires a build containing this selector.

Account sign-in and a full match were not tested.

## TFT 18.2 validation — 2026-09-10

The four verified APKs upgraded the existing 18.1 package in an isolated AVD
copy with unchanged `firstInstallTime`. The normal Mactician runtime reached
Unreal `GameActivity`, remained alive for 45 seconds with an empty crash log,
and displayed the English content-download prompt (4,175.8 MB). Account sign-in
and a full match were not tested.

The 18.2 signed game feed was published on 2026-09-10. The public manifest
passed the launcher's signature verification, and all four downloaded APKs
matched the tested sizes and SHA-256 hashes with immutable cache headers.
The launcher appcast was unchanged.

# Vietnam (VNG) edition

Settings offers Global, Vietnam (VNG), and [Taiwan](taiwan.md), remembers the last
selection, and defaults to Global. Selecting an uninstalled edition downloads it when the
shared Android runtime is already present. A fresh setup still requires the
Android SDK license step. Game language remains an independent setting.

Vietnam is a separate Android application,
[`com.riotgames.league.teamfighttacticsvn`](https://play.google.com/store/apps/details?id=com.riotgames.league.teamfighttacticsvn).
Both packages coexist in `Tft.avd` and retain separate sign-ins, files, caches,
and updates. Switching is disabled until installation, stopping, or gameplay
finishes. Reset removes all editions and the shared runtime.

## Verified release input

Prepared on 2026-09-10 from the APKPure `18.2-5450971` ARM64 XAPK.
Android manifest metadata confirms version code `8450971`.
Official Android Build Tools 36 verified the cryptographic signatures, package
IDs, split IDs, and matching version codes of all four APKs. All use the pinned
Riot certificate SHA-256:

```text
931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c
```

| APK | Bytes | SHA-256 |
| --- | ---: | --- |
| base.apk | 101626167 | d00294ae8f442586ccc46fa3d60f57ea6457df4c906381c193af2c93c15fa0ea |
| config.arm64_v8a.apk | 94106849 | 205ad469a49dcb3ceaadebd682404dce7d82cbd602502122d6e3f647608eef3f |
| config.en.apk | 37273 | 14ca6b77e7e638aeb0eb1c885b94ed48ccb5792b28cca1e2c39a79dc67ec45fd |
| config.mdpi.apk | 83007 | 0535004ea3f74f881b2a1bd6258b560b97c76e5788d441533f35073da035a8a0 |

The four private inputs live in `private/tft-apks-vietnam/`. The signed update
feed is generated with `MACTICIAN_GAME_EDITION=vietnam`; see
[the release procedure](releasing.md#publish-a-tft-game-update).

## Distribution

The VNG channel was published on 2026-09-05 with TFT `18.1-5423749`.
The existing Global feed and launcher appcast were unchanged. Existing launcher
releases continue using Global; the edition selector requires the new build.

Global keeps its bundled APKs and existing feed URL. Vietnam also ships inside
the launcher (see [Bundled release](#bundled-release--tft-184)), so a build is
never older than its bundled game and installs without downloading it; a signed
feed release replaces the bundled one only when its version code is higher. The
feed uses the same pinned game
update signing key and the path `/mactician/updates/game/vietnam/manifest.json`.
APK paths are `/mactician/updates/game/vietnam/releases/<baseSHA256>/<filename>`.
Publish this signed feed and its APKs before distributing the new launcher.
Preparation alone does not make the VNG download available to users.

The first game launch separately requests its own content download (about
4.2 GB for TFT 18.2 in the startup check), then its own sign-in. The launcher’s APK download size
does not include that content. No credentials transfer between editions.

## Initial validation (TFT 18.1)

Unit tests cover schema 1 migration to Global, schema 2 round trips with both
editions, edition selection defaults, signed cross-edition feed rejection,
exact APK URL validation, downgrade rejection, and isolated cache/overlay paths.
Runtime lifecycle fixtures exercise process polling for both Android packages.

A test copy of an existing Global AVD was used to install VNG with the production
installer. Both per-game state records survived. VNG reached Unreal GameActivity,
stayed alive for more than 25 seconds, and displayed its content-download prompt
in the selected English language with an empty crash log. Switching back to Global
and launching it from the new UI also reached GameActivity with no crash records.
The selector was disabled during gameplay and re-enabled after stopping.
Account sign-in and a
full match are separate manual checks; neither is implied by this startup test.

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

## Bundled release — TFT 18.4

Release `18.4-5673041` (version code `8673041`) is listed under `editionGames` in
`launcher/Resources/release-manifest.json` and copied to `Resources/Game-vietnam`
by `scripts/build-mactician.command`, which refuses to build unless the four
private APK splits match the manifest hashes. Inputs: the APKPure `18.4-5673041`
ARM64 XAPK, extracted to `private/tft-apks-vietnam/` (base APK renamed to
`base.apk`).

Android Build Tools 36 `apksigner` and `aapt2` verified all four APKs on
2026-10-18: package `com.riotgames.league.teamfighttacticsvn`, version code
`8673041`, matching split IDs, and the same pinned Riot certificate as 18.2
(`931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c`).

| APK | Bytes | SHA-256 |
| --- | ---: | --- |
| base.apk | 114377015 | 52a7a698976dbaea1b526cf5e3fad3a23bcd7139dce5ef995c98de9bc27d01e2 |
| config.arm64_v8a.apk | 95139041 | 8c323c77c96699f8a08d7e21c44d0c937ad7adeba463f3210b6f8604268a73a2 |
| config.en.apk | 37273 | 3caea0d581c7ad6b7bd8f935ebc076e0463f91773fd37f90f63c94360f5a04f8 |
| config.mdpi.apk | 83007 | e271ed5a2bb4b3a75372f35dc7030b6ead2746ea10e911957d5d46ddd642e39c |

Only the signatures, package, split set, and version codes were verified for this
build; an emulator launch of 18.4 was not part of the release check. The previous
bundled release was `18.4-5637330` (version code `8637330`).

An install that predates a newer bundled release is upgraded to it on the next
launch. A hosted feed that is older than the installed game is reported as up to
date instead of failing the update check. To move to a newer VNG build, replace
the `editionGames.vietnam` entry and the private APKs together.

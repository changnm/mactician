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

The four private inputs live in `private/tft-vietnam-apks/`. The signed update
feed is generated with `MACTICIAN_GAME_EDITION=vietnam`; see
[the release procedure](releasing.md#publish-a-tft-game-update).

## Distribution

The VNG channel was published on 2026-09-05 with TFT `18.1-5423749`.
The existing Global feed and launcher appcast were unchanged. Existing launcher
releases continue using Global; the edition selector requires the new build.

Global keeps its bundled APKs and existing feed URL. Vietnam is downloaded on
demand and has no bundled Global fallback. Its feed uses the same pinned game
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

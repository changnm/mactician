# Performance experiments — 2026-09-08

The integrated Vulkan buffer-view cache increases median FPS from **41.34 to
59.48 (+43.9%)** in an unchanged planning scene. Median p95 frame time falls
from **34.06 to 18.67 ms**. Eight counterbalanced windows in one game process
all passed mode, scene, graphics and host-state checks. Two early Trial fights
with opposite switch orders also improved: **27.76→44.14 FPS (+59.0%)** and
**24.76→42.69 FPS (+72.4%)**. These are measured local scenes, not a universal
late-PvP estimate. The iPad route is excluded per the owner's completed investigation.

## Session persistence fixed locally

TFT 18.1-5423749 ships the reflected Riot setting `bPersistLogin` disabled.
The launcher now adds the following to generated `Engine.ini` before starting
TFT, alongside its existing UI-scale configuration:

```ini
[/Script/OnlineSubsystemRiot.RGIOPRiotGamesApiSettings]
bPersistLogin=True
```

TFT may normalize the generated configuration later, so the setting must be
reapplied at launch. The helper preserves unrelated settings and is idempotent;
launcher tests and Swift typechecking pass. This uses the game's session store.
The launcher does not save account passwords or copy authentication tokens.

After one authorized login, **two direct cold starts reached the lobby without
a credential-entry WebView**. Two further direct cold starts with both fixes
also reached the lobby and completed verified cleanup.

`RuntimeController.start` refreshes `runtime-project` from the application's
`RuntimeTemplate` on **every Play**, so patching only the runtime is insufficient.
The local installed application's template now contains both fixes. Its original
launcher executable code is unchanged; the bundle was signed again with the
same Developer ID and hardened-runtime setting, and its original signed copy
was retained. This is a local build, without a new notarization submission or
public release. The source and bundling changes must accompany the next launcher
release so a later application update retains them.
See the [validation receipt](../artifacts/riot-session-persistence-validation-20260908.json).

Two actual **Play** launches in the installed application reached the lobby
without credential entry and verified the cache in the game process. They used
the owner's unchanged settings: 3840×2160, Maximum FPS, UI 150%, 8 vCPUs and
16 GiB. These are startup/login/rendering checks; the paired FPS results below
use 2560×1440, 7 vCPUs and 6 GiB.

The existing GUI Stop path sends `emu kill` before root cleanup completes, so
its first stop left the durable journal. The second Play successfully recovered
that journal before applying a fresh transaction. Final graceful shutdown also
verified restoration of the cache settings, staged library and AVD configuration.

## Buffer-view creation is the new lead

The exact guest ANGLE revision is
`1166eec4c0b125e9e945196acfc549983ef72b18`. Its texture-buffer synchronization
releases and recreates Vulkan buffer views when the texture is updated. In a
current-game diagnostic trace, `vkCreateBufferView` accounts for 18.75% of
all CPU samples through the RHI thread; the operation waits for the host.
This is a CPU sample share, not the fraction of frame time that can be recovered.
It concerns texture buffers, and does not validate the earlier uniform-buffer
pool hypothesis.

The first cache retained released views, keyed by device, buffer, format,
offset, range, and flags. The integrated version also shares identical active
views with reference counting, as permitted by Vulkan when private-data support
is disabled. Both bypass custom allocators and extension chains. Buffer
destruction purges released views and retires outstanding ones; device teardown
purges the cache. See [the implementation and test contract](../native/vulkan-buffer-view-cache/README.md).

### Integrated implementation

Tockers Trials 1-5 planning, Maximum FPS profile, full-resolution 2560×1440 UI,
67% 3D scale, 7 vCPUs, 6144 MB, Apple M1 Max:

| Mode | Individual two-second FPS windows | Median FPS | Median mean frame | Median p95 | Median p99 |
| --- | --- | ---: | ---: | ---: | ---: |
| Cache off | 41.636, 41.652, 41.047, 40.119 | 41.342 | 24.190 ms | 34.060 ms | 34.958 ms |
| Shared cache on | 59.536, 59.526, 59.357, 59.426 | 59.476 | 16.813 ms | 18.667 ms | 19.445 ms |

Order: off/on/on/off/on/off/off/on. This is the built standard Android Vulkan
layer, SHA-256 `8595828c89e232f737850f21fe03336714ea728e41ec876364aca8cdd7052baa`,
loaded by the source launcher's journaled integration. The same roster, items,
board and loot remained visible; before/after images show no obvious corruption.
All graphics metadata and the live library hash were verified. Normal cleanup
restored the original settings, removed the staged library and stopped the AVD.
This is an early Trial scene, not a late-PvP guarantee.

The final shared layer also passed two stage-1-8 combat comparisons:

| Switch order | Cache off FPS | Cache on FPS | Gain for on | p95 off → on | p99 off → on |
| --- | ---: | ---: | ---: | ---: | ---: |
| Off → on | 27.759 | 44.139 | +59.0% | 50.330 → 33.850 ms | 50.464 → 35.809 ms |
| On → off | 24.763 | 42.692 | +72.4% | 52.287 → 34.582 ms | 65.445 → 47.991 ms |

Each row uses the first two accepted two-second windows in one fight and one
game process. Later windows failed the scene gates and are excluded. The fights
had different friendly rosters; capture intervals were about nine seconds.
Opposite orders support the effect despite changing combat load, but two early
fights do not establish a precise gain across all match stages.

The native lifecycle/refcount, eight-thread stress, multiple-instance dispatch,
private-data bypass and transaction failure-injection tests pass. The launcher
unit tests and Swift typecheck pass. An ad-hoc application/DMG build also passes
code-signature verification; no public release has been made.

Both 65,536- and 262,144-entry builds passed Android HWASan/UBSan and 1,024
asynchronous GPU readbacks each, including an on/off/on transition. The real
guest-ANGLE probe checks duplicate active views, buffer orphaning, format/range
changes and texture recreation. The 65,536-entry integration also recovered
after an external emulator shutdown: the next cold start with the cache disabled
restored the original settings, removed the staged library and journal, and
started TFT without the layer. See the [correctness receipt](../artifacts/vulkan-buffer-view-cache-validation-20260908.json).

### Capacity screen

A 262,144-entry build passed the same native and GPU correctness checks. Its
one accepted stage-1-8 off→on pair measured **24.444→38.449 FPS (+57.3%)**.
Later windows failed the scene gates and are excluded. This supports caching
but does not demonstrate an additional benefit over 65,536 entries; the roster
differed from the earlier fights. The default remains the smaller, more
extensively tested cache. Both the new and old library hashes and all accepted
and rejected windows are retained in the measurement receipt.

### Earlier released-view prototype

Tockers Trials 1-5, Maximum FPS profile, full-resolution 2560×1440 UI,
67% 3D scale, 7 vCPUs, 6144 MB, Apple M1 Max:

| Mode | Individual two-second FPS windows | Median FPS | Median mean frame | Median p95 |
| --- | --- | ---: | ---: | ---: |
| Cache off | 39.8, 38.7, 39.0, 38.0 | 38.85 | 25.745 ms | 34.570 ms |
| Cache on, 65,536 entries | 51.6, 52.0, 54.1, 52.7 | 52.35 | 19.100 ms | 33.283 ms |

Order: off/on/on/off/on/off/off/on. Every block attested the active mode in the
same process and passed before/after scene gates; host power and thermal state
were stable, and cleanup was verified. The visible roster and scene remained
the same. The result establishes a local planning-scene effect, not a general
late-PvP multiplier. See the [measurement receipt](../artifacts/vulkan-buffer-view-cache-screen-20260908.json).

Separate-boot Trial 1-8 measurements were 28.3 FPS control, 32.4 FPS with a
4,096-entry cache, and 34.4 FPS with 16,384 entries. Friendly rosters differed,
so those numbers are exploratory and cannot establish the gain. The first
same-fight capture was rejected as a comparison because the collector's metadata
work consumed too much of the fight before both modes were measured.

The released-view standard layer subsequently won in two fights with opposite
orders: off→on **28.283→39.713 FPS (+40.4%)**, and on→off **38.797→30.497 FPS
(+27.2% for on)**. Only scene-valid windows count. Opposite orders reduce the
explanation that later windows merely contain fewer surviving units; different
rosters and capture overhead still limit the precision of this combat estimate.
These two fights used the earlier released-view library, not the final shared
implementation. Three shared-prototype attempts ended before 1-8 and yielded
no accepted FPS measurements.

### Other candidates

The latest KosmicKrisp passed the tested guest-ANGLE draw workload but was much
slower than the packaged MoltenVK in that synthetic screen. This rejects that
host-driver substitution for the present path; it does not answer whether a
future native GLES transport can benefit from host ANGLE/KosmicKrisp.
MoltenVK 1.4.2 and queued RHI commands have no confirmed game win yet.
See the [driver screen](../artifacts/android-host-driver-screen-20260908.json).

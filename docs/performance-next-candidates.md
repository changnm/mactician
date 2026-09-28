# Additional performance candidates — 2026-09-06

September 8 update: the trace-led buffer-view cache now leads the queue.
See [overnight experiments and current evidence](performance-experiments-20260908.md).
The dated investigation below is retained as research context.

This pass found three additional experiments and one conditional hitch-reduction
investigation. None has an FPS result or belongs in a production preset yet.
The existing OpenGL UBO pool and queued RHI command-list experiments remain
ahead of these in the overall queue because they have more local evidence.

For larger changes to the graphics/runtime architecture, see
[Structural performance opportunities](performance-structural-opportunities.md),
including the new local host ANGLE/KosmicKrisp capability result.

## Evidence boundary

The current release manifest pins Global TFT **18.1-5423749**. Its ARM64 split
was verified against the manifest and its unmodified `libUnreal.so` was inspected
offline. That library hashes to
`6e8e48bdd913a9ce80ce07c3deef48ffb808b12ee34addfe497b181327907667`;
the August PBE audits used a different library. Their addresses and effective
defaults cannot be reused for this release.

ANGLE source was fetched at commit
`1166eec4c0b125e9e945196acfc549983ef72b18`, the exact revision reported by the
retained August GLES probe. It establishes behavior for that revision, not
attestation of a newly launched September process. Initial ELF storage values
are likewise not runtime values: configuration and game code may override them.

The [machine-readable audit](../artifacts/performance-candidate-source-audit-20260906.json)
records hashes, registration addresses, initial storage, source references, and
unresolved checks. This investigation did not launch TFT or run benchmarks.

## New experiments, in screening order

| Priority | Isolated change | Why it might help | First rejection gate |
| --- | --- | --- | --- |
| 1 | ANGLE `preferHostCachedForNonStaticBufferUsage` | Requests CPU-cached memory for dynamic/stream draw buffers and host-visible internal dynamic buffers; could lower CPU access cost in the upload path | Reject as a no-op if the selected guest Vulkan memory type does not change |
| 2 | `Slate.EnableGlobalInvalidation=1` | Reuses unchanged UI layout/paint data, potentially reducing CPU work for the HUD, shop, and other widgets | Query the effective value first; then reject stale counters, missing widgets, or broken hit testing |
| 3 | `OpenGL.UseStagingBuffer=1` | Routes dynamic vertex-buffer mapping through staging storage; could change map/copy/wait costs for geometry uploads | Query the effective value and prove the path is used; reject increased copy/barrier cost or geometry corruption |

### 1. ANGLE memory selection

In this exact revision, `FeatureInfo` starts disabled and `Renderer::initFeatures`
does not enable `preferHostCachedForNonStaticBufferUsage`. `BufferVk.cpp`
uses the flag when choosing memory for `DynamicDraw` and `StreamDraw`;
`vk_helpers.cpp` also consults it for host-visible `DynamicBuffer` allocations.
This differs from the already rejected `preferCPUForBufferSubData` copy strategy.

On a unified-memory Mac, the guest can still expose multiple Vulkan memory
types, and adding the cached preference may select the same type. Record
`VkPhysicalDeviceMemoryProperties`, selected allocation types, the effective
ANGLE feature, and allocation counts before assigning any mechanism or gain.
Try the existing draw/UBO probes with an interleaved control-candidate-control
screen; only a repeatable survivor proceeds to real combat.

Sources: [feature initialization](https://chromium.googlesource.com/angle/angle/+/1166eec4c0b125e9e945196acfc549983ef72b18/include/platform/Feature.h),
[buffer memory selection](https://chromium.googlesource.com/angle/angle/+/1166eec4c0b125e9e945196acfc549983ef72b18/src/libANGLE/renderer/vulkan/BufferVk.cpp),
[internal dynamic buffers](https://chromium.googlesource.com/angle/angle/+/1166eec4c0b125e9e945196acfc549983ef72b18/src/libANGLE/renderer/vulkan/vk_helpers.cpp).

### 2. Slate global invalidation

The current TFT library registers the CVar against zero-initialized storage;
ordinary invalidation panels have initial value 1. Global invalidation is a
separate mechanism, so enabling panels again would miss the opportunity.
First query the effective global value after login and in a match. If it is
already enabled, discard this candidate.

Epic documents window-level caching and explains that enabling it deactivates
the nested invalidation boxes. It therefore needs UI correctness checks for HP,
gold, timer, shop changes, tooltips, drag/drop, selling, and reconnect. Measure
GameThread/Slate cost as well as combat pacing; an RHI-limited scene may see no
FPS improvement even if the UI becomes cheaper. Do not combine this experiment
with `Slate.EnableFastWidgetPath` or UI tick-rate changes.

Riot's VALORANT implementation is useful precedent, but its reported gains
followed game-specific fixes and do not predict TFT gains.
Sources: [Epic UI invalidation](https://dev.epicgames.com/documentation/en-us/unreal-engine/invalidation-in-slate-and-umg-for-unreal-engine),
[Riot's implementation report](https://playvalorant.com/en-gb/news/dev/performance-boost-valorant-s-global-invalidation/).

### 3. Dynamic geometry staging

The current TFT library registers `OpenGL.UseStagingBuffer` with initial storage
0 and describes it as staging for dynamic vertex-buffer maps. The adjacent
`OpenGL.UseMapBuffer` reference has initial value 1. August's separate runtime
audit also found staging disabled, but that is not a current-release runtime
attestation.

This targets vertex uploads, whereas `OpenGL.UBOPoolSize` targets uniforms.
An extra staging copy can be slower. Confirm use of the staging path, buffer
sizes, map/copy calls, and RHI waits before a full A/B. A positive UBO-only
microbenchmark does not validate this geometry experiment.

## Conditional investigation: shader-cache write/remap hitches

The current library exposes initial values of **20 programs** for
`r.OpenGL.BinaryCachePeriodicFlushProgramCount` and **50 MB** for
`r.OpenGL.BinaryCacheMMapAfterEveryMB`. Embedded descriptions restrict these
controls to the PSO-precaching path: one controls appending/flushing programs,
the other controls remapping the growing cache and releasing unused program
allocations.

Only investigate larger thresholds if a trace correlates long frames with
these operations and confirms that PSO precaching is active. Test one threshold
at a time. Less frequent writes/remaps can retain more RAM and postpone a larger
stall; the outcome is about p99/long frames during cache growth, not a promised
increase in sustained late-combat FPS. Keep the persistent cache intact and
compare equivalent cache states.

## Ideas eliminated during this pass

At the retained ANGLE revision, persistent buffer mapping, asynchronous command
buffer reset/garbage cleanup, and descriptor-set caching on non-SwiftShader
devices are already enabled by source defaults. Their enablement is not a new
optimization. The current TFT ELF also starts deferred retained Slate rendering
at 1. Effective runtime overrides remain a separate question.

The [official Emulator release notes](https://developer.android.com/studio/releases/emulator)
still list the repository's pinned 37.1.11 as the latest stable entry inspected
in this pass; a generic recommendation to upgrade the emulator adds no concrete
candidate.

## Acceptance

Reattest the current APK, effective profile, driver revision, and intended
non-noop change. Use the existing [benchmark methodology](benchmarks.md):
matched scenes, stable host power/thermal conditions, repeated cold runs,
frame-tail checks, visual correctness, and verified rollback. Preserve the
distinction between synthetic screening, Trial results, and late-PvP results.
No executable profiles or production defaults were changed by this research.

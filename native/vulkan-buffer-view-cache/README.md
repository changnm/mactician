# Vulkan buffer-view cache

This Android layer removes repeated synchronous `vkCreateBufferView` trips from
guest ANGLE through gfxstream to MoltenVK. The exact tested ANGLE revision is
`1166eec4c0b125e9e945196acfc549983ef72b18`; its texture-buffer synchronization
discards views even when the next view has the same buffer, format and range.
The [experiment report](../../docs/performance-experiments-20260908.md) separates
measured game results from exploratory screens.

The bounded table has 65,536 entries, four ways per bucket, and reverse indexes
for view destruction and buffer retirement. Its key includes device, buffer,
format, offset, range and flags. It bypasses extension chains and custom
allocators. Retained driver views are destroyed on eviction, buffer destruction
or device teardown. Views still referenced by the caller survive buffer
retirement but cannot be reused by a new buffer with the same handle.

Identical active views can share a handle with reference counting. The Vulkan
[object model](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html)
allows identical non-dispatchable handles when `privateData` is disabled, as
long as destruction does not invalidate outstanding references. This layer
bypasses caching whenever any device in the process enables that feature.
The tested target is the pinned Android ANGLE/gfxstream/MoltenVK path; this is
not a general driver compatibility claim.

## Build and tests

```sh
export TFT_ANDROID_NDK="$ANDROID_HOME/ndk/27.3.13750724"
./scripts/build-vulkan-view-cache.command
./scripts/test-vulkan-view-cache.command
```

The library and SHA-256 file are generated in `runtime/vulkan-buffer-view-cache`
and bundled by the launcher builder. The NDK revision is checked, ARM64 API 30
is targeted, and ELF segments use 16 KiB maximum page alignment. No game APK or
game executable is changed by this layer.

`test.c` checks lifetimes, reference counts, buffer retirement/handle reuse,
capacity/eviction, bypasses, live mode changes and eight concurrent callers.
`dispatch-test.c` checks separate instances/devices, loader-chain advancement,
forwarding, failed creation and private-data device tracking.
`test-vulkan-cache-transaction.py` injects failures during activation and
recovery, and checks preservation of foreign settings and invalid journals.
The host tests also enable UndefinedBehaviorSanitizer. On the pinned Android
36 guest, the lifecycle/eight-thread test passes with HWAddressSanitizer and
UBSan for both 65,536 and 262,144 entries. Compile `test.c` with
`-fsanitize=hwaddress,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer`
and `-llog`, then run the executable with `LD_HWASAN=1` on Android 14 or newer;
see the [NDK instructions](https://developer.android.com/ndk/guides/hwasan).

`gpu-readback-test.c` exercises the real guest ANGLE path: 1,024 asynchronous
texture-buffer compute readbacks, duplicate active views, R32UI/RGBA32UI,
different offsets/ranges, orphaning, and texture deletion/recreation. Compile
with the pinned NDK's `aarch64-linux-android30-clang -std=c11 -O2`, linking
`-lEGL -lGLESv3`. Run it in an isolated emulator with the same ANGLE features
as TFT, once without the layer and once while toggling the cache on/off/on.
Native GPU probes use `debug.vulkan.layers`; never use that global activation
for normal TFT launches.

## Launch and recovery

`guest-vulkan-view-cache.sh` uses Android's
[app-targeted Vulkan layer settings](https://developer.android.com/ndk/guides/graphics/validation-layer).
The layer is staged in the installed game's extracted native library directory,
where the Android loader can execute it under its normal SELinux policy.
The launcher checks the local and guest SHA-256 and confirms the mapping in
the TFT process. A durable root-owned journal records the original settings
before changes; normal shutdown and the next cold launch both recover it.
Recovery also runs when the new launch disables the cache.

`TFT_VULKAN_VIEW_CACHE=0` disables installation. With the layer loaded,
`debug.mactician.vk_view_cache` switches reuse on (`1`) or off (`0`) while
destruction still tracks retained objects. It is polled every 64 create calls
per thread. Mode changes and aggregate counts are logged under `MacticianVkView`.
`tools/capture-vulkan-cache-pairs.py` captures mode-attested windows in one TFT
process and defers OCR/metadata until after the timed sequence. Independent
fights with opposite orders are needed to assess changing combat load.

#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly NDK="${TFT_ANDROID_NDK:-${ANDROID_NDK_HOME:-}}"
readonly OUTPUT="${1:-$PROJECT_DIR/runtime/vulkan-buffer-view-cache}"
readonly NDK_REVISION=27.3.13750724

if [[ -z "$NDK" || ! -f "$NDK/source.properties" ]] \
        || ! grep -Fxq "Pkg.Revision = $NDK_REVISION" "$NDK/source.properties"; then
    print -u2 "Set TFT_ANDROID_NDK to Android NDK r27d ($NDK_REVISION)."
    exit 2
fi
case "$(uname -s)" in
    Darwin) readonly TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64" ;;
    Linux) readonly TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64" ;;
    *) print -u2 'Unsupported NDK build host.'; exit 2 ;;
esac
readonly COMPILER="$TOOLCHAIN/bin/aarch64-linux-android30-clang"
readonly LIBRARY="$OUTPUT/libVkLayer_Mactician_buffer_view_cache.so"
mkdir -p "$OUTPUT"
"$COMPILER" -std=c11 -O2 -Wall -Wextra -Werror \
    -fvisibility=hidden -fPIC -shared -Wl,-Bsymbolic \
    -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 \
    -Wl,-soname,libVkLayer_Mactician_buffer_view_cache.so \
    "$PROJECT_DIR/native/vulkan-buffer-view-cache/layer.c" \
    -o "$LIBRARY" -llog
shasum -a 256 "$LIBRARY" | awk '{ print $1 }' > "$LIBRARY.sha256"
print "$LIBRARY"

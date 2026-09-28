#!/bin/zsh
set -euo pipefail
readonly PROJECT_DIR="${0:A:h:h}"
readonly NDK="${TFT_ANDROID_NDK:-${ANDROID_NDK_HOME:-}}"
readonly WORK="$(mktemp -d -t mactician-vulkan-cache-tests)"
trap 'rm -rf "$WORK"' EXIT

"$PROJECT_DIR/scripts/build-vulkan-view-cache.command" "$WORK/android" >/dev/null
case "$(uname -s)" in
    Darwin) readonly TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64" ;;
    Linux) readonly TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64" ;;
esac
# Use the pinned NDK's Vulkan declarations with the host's C standard library.
mkdir -p "$WORK/include"
cp -R "$TOOLCHAIN/sysroot/usr/include/vulkan" "$TOOLCHAIN/sysroot/usr/include/vk_video" "$WORK/include/"
for test in test dispatch-test; do
    "${CC:-clang}" -std=c11 -O2 -Wall -Wextra -Werror -pthread \
        -fsanitize=undefined -fno-sanitize-recover=all \
        -I "$WORK/include" "$PROJECT_DIR/native/vulkan-buffer-view-cache/$test.c" \
        -o "$WORK/$test"
    "$WORK/$test" > "$WORK/$test.log" 2>&1 || { cat "$WORK/$test.log"; exit 1; }
    tail -c 220 "$WORK/$test.log"
done
python3 "$PROJECT_DIR/scripts/test-vulkan-cache-transaction.py"

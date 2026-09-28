#!/bin/zsh

# Shared Android tool discovery for source-tree launch and diagnostic scripts.
# Set TFT_ANDROID_SDK_ROOT or TFT_ROOT_SDK to select a non-standard SDK.

tft_resolve_android_sdk_root() {
    local explicit_root="${TFT_ROOT_SDK:-${TFT_ANDROID_SDK_ROOT:-}}"
    local candidate

    for candidate in \
        "$explicit_root" \
        "${ANDROID_SDK_ROOT:-}" \
        "${ANDROID_HOME:-}" \
        "$HOME/Library/Android/sdk"; do
        if [[ -n "$candidate" && -d "$candidate" ]]; then
            print -r -- "$candidate"
            return 0
        fi
    done

    local adb_path
    adb_path="$(command -v adb 2>/dev/null || true)"
    if [[ -n "$adb_path" ]]; then
        print -r -- "${adb_path:A:h:h}"
        return 0
    fi

    print -u2 "Android SDK was not found. Set TFT_ANDROID_SDK_ROOT, ANDROID_SDK_ROOT, or ANDROID_HOME."
    return 1
}

tft_resolve_adb() {
    if [[ -n "${TFT_ADB:-}" ]]; then
        if [[ -x "$TFT_ADB" ]]; then
            print -r -- "$TFT_ADB"
            return 0
        fi
        print -u2 "TFT_ADB is set but is not executable: $TFT_ADB"
        return 1
    fi

    local sdk_root adb_path
    sdk_root="$(tft_resolve_android_sdk_root)" || return 1
    adb_path="$sdk_root/platform-tools/adb"
    if [[ -x "$adb_path" ]]; then
        print -r -- "$adb_path"
        return 0
    fi

    adb_path="$(command -v adb 2>/dev/null || true)"
    if [[ -n "$adb_path" && -x "$adb_path" ]]; then
        print -r -- "$adb_path"
        return 0
    fi

    print -u2 "ADB was not found. Set TFT_ADB or install platform-tools under the selected Android SDK."
    return 1
}

tft_resolve_emulator() {
    if [[ -n "${TFT_EMULATOR:-}" ]]; then
        if [[ -x "$TFT_EMULATOR" ]]; then
            print -r -- "$TFT_EMULATOR"
            return 0
        fi
        print -u2 "TFT_EMULATOR is set but is not executable: $TFT_EMULATOR"
        return 1
    fi

    local sdk_root emulator_path
    sdk_root="$(tft_resolve_android_sdk_root)" || return 1
    emulator_path="$sdk_root/emulator/emulator"
    if [[ -x "$emulator_path" ]]; then
        print -r -- "$emulator_path"
        return 0
    fi

    emulator_path="$(command -v emulator 2>/dev/null || true)"
    if [[ -n "$emulator_path" && -x "$emulator_path" ]]; then
        print -r -- "$emulator_path"
        return 0
    fi

    print -u2 "Android Emulator was not found. Set TFT_EMULATOR or install it in the selected Android SDK."
    return 1
}

tft_resolve_avd_home() {
    print -r -- "${TFT_AVD_HOME:-${ANDROID_AVD_HOME:-$HOME/.android/avd}}"
}

# Only supported, independently signed live applications may enter guest commands.
tft_resolve_game_package() {
    local game_package="${TFT_GAME_PACKAGE:-com.riotgames.league.teamfighttactics}"
    case "$game_package" in
        com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn|com.riotgames.league.teamfighttacticstw)
            print -r -- "$game_package"
            ;;
        *)
            print -u2 "Unsupported TFT game package: $game_package"
            return 2
            ;;
    esac
}

#!/system/bin/sh
# Runs as root in the dedicated Android userdebug AVD, with TFT stopped.
# The journal is durable before settings or the app's native library directory
# change. Never source it: every field is read and validated as data.
set -eu
umask 077

action=${1:-}
package=${2:-}
case "$package" in
    com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn|com.riotgames.league.teamfighttacticstw) ;;
    *) echo 'Unsupported Vulkan-cache package.' >&2; exit 2 ;;
esac
directory=/data/local/tmp/mactician-vulkan-cache-$package
journal=$directory/state
layer=VK_LAYER_MACTICIAN_buffer_view_cache
property=debug.mactician.vk_view_cache

fail() { echo "Vulkan-cache transaction: $*" >&2; exit 1; }
safe_value() {
    case "$1" in *[!A-Za-z0-9_.:-]*) return 1 ;; esac
}
setting() { settings get global "$1"; }
put_setting() {
    if [ "$2" = null ]; then settings delete global "$1" >/dev/null
    else settings put global "$1" "$2"; fi
    [ "$(setting "$1")" = "$2" ] || fail "could not verify $1"
}
validate() {
    [ "$version" = 1 ] || fail 'unknown journal version'
    [ "$saved_package" = "$package" ] || fail 'journal package differs'
    case "$remote" in
        /data/app/*/"$package"-*/lib/arm64/libVkLayer_Mactician_buffer_view_cache.so) ;;
        *) fail 'invalid native library path' ;;
    esac
    case "$remote" in *[!A-Za-z0-9_~./=+-]*|*/../*|*/./*) fail 'unsafe native library path' ;; esac
    [ "${#sha}" = 64 ] || fail 'invalid library hash'
    case "$sha" in *[!0-9a-f]*) fail 'invalid library hash' ;; esac
    case "$old_enable" in null|0|1) ;; *) fail 'invalid original layer state' ;; esac
    safe_value "$old_app" && safe_value "$old_layers" || fail 'unsafe original layer settings'
    case "$old_mode" in ''|0|1) ;; *) fail 'invalid original cache mode' ;; esac
}
read_journal() {
    [ -f "$journal" ] && [ ! -L "$journal" ] || fail 'journal is not a regular file'
    [ "$(stat -c '%u:%a' "$journal")" = 0:600 ] || fail 'unexpected journal ownership'
    exec 3< "$journal"
    IFS= read -r version <&3 && IFS= read -r saved_package <&3 \
        && IFS= read -r remote <&3 && IFS= read -r sha <&3 \
        && IFS= read -r old_enable <&3 && IFS= read -r old_app <&3 \
        && IFS= read -r old_layers <&3 && IFS= read -r old_mode <&3 \
        || fail 'truncated journal'
    if IFS= read -r extra <&3; then fail 'extra journal fields'; fi
    exec 3<&-
    validate
}
check_current_settings() {
    now_enable=$(setting enable_gpu_debug_layers)
    now_app=$(setting gpu_debug_app)
    now_layers=$(setting gpu_debug_layers)
    now_mode=$(getprop "$property")
    case "$now_enable" in "$old_enable"|0|1) ;; *) fail 'layer state changed outside this transaction' ;; esac
    case "$now_app" in "$old_app"|"$package") ;; *) fail 'another debug app replaced this transaction' ;; esac
    case "$now_layers" in "$old_layers"|"$layer") ;; *) fail 'another layer replaced this transaction' ;; esac
    case "$now_mode" in ''|0|1) ;; *) fail 'cache property changed outside this transaction' ;; esac
}

[ "$(id -u)" = 0 ] || fail 'requires the dedicated rootable AVD'
[ -z "$(pidof "$package" || true)" ] || fail 'stop TFT before changing its Vulkan layer'
if [ -e "$directory" ]; then
    [ -d "$directory" ] && [ ! -L "$directory" ] || fail 'unsafe journal directory'
    [ "$(stat -c '%u:%a' "$directory")" = 0:700 ] || fail 'unexpected directory ownership'
fi

case "$action" in
    recover)
        [ -e "$journal" ] || exit 0
        read_journal
        check_current_settings
        # Disabling first also makes interruption at any following step safe.
        put_setting enable_gpu_debug_layers 0
        put_setting gpu_debug_app "$old_app"
        put_setting gpu_debug_layers "$old_layers"
        put_setting enable_gpu_debug_layers "$old_enable"
        setprop "$property" "$old_mode"
        [ "$(getprop "$property")" = "$old_mode" ] || fail 'cache mode was not restored'
        [ ! -L "$remote" ] || fail 'staged library became a symbolic link'
        rm -f "$remote"
        [ ! -e "$remote" ] || fail 'staged library remains'
        sync
        rm -f "$journal"
        sync
        echo 'Vulkan-cache settings and staged library restored and verified.'
        ;;
    prepare)
        [ ! -e "$journal" ] || fail 'recover the previous transaction first'
        version=1
        saved_package=$package
        sha=${3:-}
        base=$(pm path "$package" | sed -n 's/^package:\(.*\/base\.apk\)$/\1/p')
        remote=${base%/base.apk}/lib/arm64/libVkLayer_Mactician_buffer_view_cache.so
        old_enable=$(setting enable_gpu_debug_layers)
        old_app=$(setting gpu_debug_app)
        old_layers=$(setting gpu_debug_layers)
        old_mode=$(getprop "$property")
        validate
        # This AVD normally has no Vulkan debug layers. Preserve an existing
        # developer setup instead of temporarily taking it over.
        [ "$old_enable" != 1 ] || fail 'Vulkan debug layers are already enabled'
        [ ! -e "$remote" ] && [ ! -L "$remote" ] || fail 'native library destination already exists'
        [ -d "${remote%/*}" ] || fail 'TFT native library directory is absent'
        mkdir -p "$directory"
        chmod 700 "$directory"
        printf '%s\n' "$version" "$saved_package" "$remote" "$sha" \
            "$old_enable" "$old_app" "$old_layers" "$old_mode" > "$journal.tmp"
        chmod 600 "$journal.tmp"
        mv "$journal.tmp" "$journal"
        sync
        printf '%s\n' "$remote"
        ;;
    activate)
        read_journal
        [ "$(setting enable_gpu_debug_layers)" = "$old_enable" ] \
            && [ "$(setting gpu_debug_app)" = "$old_app" ] \
            && [ "$(setting gpu_debug_layers)" = "$old_layers" ] \
            || fail 'settings changed while the library was being staged'
        [ -f "$remote" ] && [ ! -L "$remote" ] || fail 'staged library is absent'
        [ "$(sha256sum "$remote" | cut -d ' ' -f 1)" = "$sha" ] || fail 'staged library hash differs'
        chown 0:0 "$remote"
        chmod 644 "$remote"
        chcon u:object_r:apk_data_file:s0 "$remote"
        put_setting enable_gpu_debug_layers 0
        put_setting gpu_debug_app "$package"
        put_setting gpu_debug_layers "$layer"
        setprop "$property" 1
        [ "$(getprop "$property")" = 1 ] || fail 'cache mode was not applied'
        put_setting enable_gpu_debug_layers 1
        sync
        echo 'Vulkan buffer-view cache enabled for TFT.'
        ;;
    *) fail 'expected prepare, activate, or recover' ;;
esac

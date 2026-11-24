#!/usr/bin/env bash
# Swaps the Bluetooth module (/system/apex/com.android.bt.capex) on the OnePlus 8, crDroid 16 v12.9-20260424 only.
#
#   ./btapex.sh status              Booted into Android: which module is installed and what's active.
#   ./btapex.sh install unchanged   In recovery: crDroid's module repacked with our key (pipeline test).
#   ./btapex.sh install patched     In recovery: our key + the dual-A2DP patch.
#   ./btapex.sh restore             In recovery: put crDroid's original back.
#
# Recovery: tap "Mount system" and "Advanced > Enable ADB" first. The phone's current module must be one
# of the three known files below; anything else (another crDroid build) is refused, because the patch is
# built for this exact library.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: hand phone paths to adb.exe untouched (see native())

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPEX=/mnt/system/system/apex/com.android.bt.capex

file_for() {  # original|unchanged|patched -> the local file (bash 3.2 on macOS has no associative arrays)
    case $1 in
        original)  echo "$HERE/apex/com.android.bt.capex" ;;
        unchanged) echo "$HERE/out/unchanged/com.android.bt.capex" ;;
        patched)   echo "$HERE/out/patched/com.android.bt.capex" ;;
    esac
}

say()    { printf '\033[1m==>\033[0m %s\n' "$*"; }
die()    { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
rsh()    { adb shell "$*" </dev/null | tr -d '\r'; }
sha()    { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
native() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }  # a local path adb can open

known_name() {  # sha -> original|unchanged|patched|''
    local s=$1 k
    for k in original unchanged patched; do [ "$(sha "$(file_for $k)")" = "$s" ] && { echo "$k"; return 0; }; done
    return 0   # unknown: print nothing (callers check for empty), but don't trip set -e
}

need_state() {
    local got; got=$(adb get-state 2>/dev/null || true)
    [ "$got" = "$1" ] || die "phone isn't in '$1' over ADB (state: ${got:-none})"
}

become_root() {
    [ "$(rsh id -u)" = 0 ] && return
    adb root >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do sleep 1; [ "$(rsh id -u 2>/dev/null)" = 0 ] && return; done
    die "couldn't get a root shell in recovery"
}

dim_recovery() {  # 2% backlight, held until reboot (same as apply.sh)
    rsh 'B=/sys/class/backlight/panel0-backlight; [ -w $B/brightness ] || exit 0
        P=/tmp/op8-dim.pid; [ -f $P ] && kill $(cat $P) 2>/dev/null
        L=$(( ($(cat $B/max_brightness) * 2 + 50) / 100 ))
        nohup sh -c "while :; do [ \"\$(cat $B/brightness)\" = $L ] || echo $L > $B/brightness; sleep 0.3; done" >/dev/null 2>&1 &
        echo $! > $P' >/dev/null || true
}

mount_rw() {
    local dev; dev=$(rsh "grep ' /mnt/system ' /proc/mounts | cut -d' ' -f1")
    [ -n "$dev" ] || die "system isn't mounted: tap 'Mount system' in recovery first"
    rsh "blockdev --setrw $dev; mount -o remount,rw /mnt/system" >/dev/null || true
    rsh "touch /mnt/system/system/apex/.rw && rm /mnt/system/system/apex/.rw && echo ok" | grep -q ok || die "couldn't make system writable"
}
mount_ro() { rsh "sync; mount -o remount,ro /mnt/system" >/dev/null || true; }

swap_to() {  # $1 = original|unchanged|patched
    local want=$1 src cur cur_name label new_sha
    src=$(file_for "$want")
    [ -f "$src" ] || die "missing $src"
    need_state recovery; become_root; dim_recovery; mount_rw
    cur=$(rsh "sha256sum $CAPEX" | cut -d' ' -f1)
    cur_name=$(known_name "$cur")
    [ -n "$cur_name" ] || { mount_ro; die "the phone's module ($cur) isn't one this script knows; refusing"; }
    say "Installed now: $cur_name"
    if [ "$cur_name" = "$want" ]; then mount_ro; say "Already $want; nothing to do."; return; fi
    label=$(rsh "ls -Z $CAPEX" | awk '{print $1}')
    [[ "$label" == u:object_r:*:s0 ]] || { mount_ro; die "couldn't read the module's SELinux label ($label)"; }
    adb push "$(native "$src")" "$CAPEX.new" >/dev/null
    new_sha=$(rsh "sha256sum $CAPEX.new" | cut -d' ' -f1)
    [ "$new_sha" = "$(sha "$src")" ] || { rsh "rm -f $CAPEX.new"; mount_ro; die "upload damaged; nothing changed"; }
    rsh "chown root:root $CAPEX.new && chmod 644 $CAPEX.new && chcon $label $CAPEX.new && touch -r $CAPEX $CAPEX.new && mv -f $CAPEX.new $CAPEX"
    [ "$(rsh "sha256sum $CAPEX" | cut -d' ' -f1)" = "$new_sha" ] || die "swap didn't take; check $CAPEX by hand"
    [ "$(rsh "ls -Z $CAPEX" | awk '{print $1}')" = "$label" ] || die "label not restored on $CAPEX"
    mount_ro
    say "Installed: $want ($label). Reboot; the first boot unpacks the module again (a few seconds longer)."
}

cmd_status() {
    need_state device
    local cur name ver dual off
    cur=$(rsh "sha256sum /system/apex/com.android.bt.capex" | cut -d' ' -f1)
    name=$(known_name "$cur"); ver=$(rsh "pm list packages --apex-only --show-versioncode | grep com.android.bt")
    dual=$(rsh "getprop debug.bt.dual_a2dp"); off=$(rsh "dumpsys bluetooth_manager | grep A2dpOffloadEnabled || true" | sed -n 1p | tr -d ' ')
    printf '  %-18s %s\n' "Module:" "${name:-UNKNOWN ($cur)}" "Package:" "${ver:-?}" \
        "A2DP offload:" "${off:-?}" "debug.bt.dual_a2dp:" "${dual:-unset (on)}"
    rsh "dumpsys bluetooth_manager | sed -n '/^A2DP Peers State:/,/^A2DP Source State/p'" | sed 's/^/    /' || true
}

case "${1:-}" in
    status)  cmd_status ;;
    install) [[ "${2:-}" =~ ^(unchanged|patched)$ ]] || die "install unchanged|patched"; swap_to "$2" ;;
    restore) swap_to original ;;
    *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

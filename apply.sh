#!/usr/bin/env bash
# Re-applies the OnePlus 8 (crDroid 16, no root) fixes after a ROM flash.
#
#   Dolby     The ROM links its Dolby service against libstagefright_foundation-v33.so
#             but doesn't ship it: the service crash-loops and the Dolby app crashes.
#   JamesDSP  Effect library + an entry in /odm/etc/audio_effects.xml, and the
#             root build of the JamesDSP app. Your speaker curve (tuned against an
#             iPhone 13) is files/jamesdsp/Oneplus_8_speakers.tar, every value written
#             out in JAMESDSP.md. 'postboot' puts it in Download/ and lists the taps to
#             use it on the phone speaker only (app settings can't be set over adb
#             without root).
#   Thermals  Skin-temperature throttling trip points lowered 4°C at boot
#             (files/thermal_tune.sh; edit the values there).
#   Haptics   Replacement vibrator HAL with amplitude control + haptic primitives
#             (source and notes in haptics-hal/, log in HAPTICS-LOG.md). Falls back to the
#             ROM's HAL by itself if it ever crashes; 'adb shell setprop
#             persist.debug.vib.stock 1' + reboot switches back to the ROM's HAL on purpose.
#             'postboot' then turns on crDroid's brightness and volume slider haptics
#             (only if this HAL is running: on the ROM's HAL they buzz).
#
# In recovery the script also holds the screen at 2% brightness until reboot
# (RECOVERY_BRIGHTNESS=<percent> ./apply.sh ... to change it, 0 to leave it alone).
#
# /odm is read-only (erofs), so the files go to /system/etc/odm_overlay and
# /system/etc/init/odm_overlay.rc overlays them onto /odm at every boot.
# No su and nothing left running as root; the thermal script runs once at boot.
#
# Usage (phone connected over USB):
#   ./apply.sh recovery   In recovery, after "Mount system" + "Enable ADB": writes the
#                         overlay, then offers to reboot and finish with 'postboot'.
#   ./apply.sh postboot   Booted into Android: installs JamesDSP, grants its permissions,
#                         offers the speaker preset, turns on slider haptics.
#   ./apply.sh status     Booted into Android: shows what's active.
#   ./apply.sh remove     In recovery: deletes the overlay (undo). Leaves the app installed.
#
# flashable/ has recovery-flashable zips that do what 'recovery' and 'remove' do
# (flashable/README.md). Edit files/ here, then rebuild them with flashable/build.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$HERE/files"
APK="$FILES/JamesDSP-v1.6.14-root.apk"
SYS=/mnt/system/system            # system-as-root, as mounted by crDroid recovery
LAYER="$SYS/etc/odm_overlay"
RC="$SYS/etc/init/odm_overlay.rc"
VIB_RC="$SYS/etc/init/vibrator_op8.rc"
VIB_BIN=android.hardware.vibrator-service.op8
STOCK_VIB=bin/hw/vendor.qti.hardware.vibrator.service.oplus
RECOVERY_BRIGHTNESS=${RECOVERY_BRIGHTNESS:-2}   # percent of max, while the script runs in recovery
V33=libstagefright_foundation-v33.so
JDSP_UUID=f27317f4-c984-4de6-9a90-545759495bf2
JDSP_PRESET="$FILES/jamesdsp/Oneplus_8_speakers.tar"
JDSP_PRESETS=/sdcard/Android/data/james.dsp/files/Presets   # the app's own preset folder

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
rsh()  { adb shell "$*" </dev/null | tr -d '\r'; }

usage() { sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"; exit "${1:-0}"; }

need_state() {
    local want=$1 got
    got=$(adb get-state 2>/dev/null || true)
    [ "$got" = "$want" ] && return
    case "$want" in
        recovery) die "phone isn't in recovery with ADB on (state: ${got:-none}). Boot to recovery, tap 'Mount system' and 'Enable ADB'." ;;
        device)   die "phone isn't booted into Android with USB debugging (state: ${got:-none})." ;;
    esac
}

become_root() {
    [ "$(rsh id -u)" = 0 ] && return
    adb root >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        sleep 1
        [ "$(rsh id -u 2>/dev/null)" = 0 ] && return
    done
    die "couldn't get a root shell in recovery ('adb root' failed)"
}

# Recovery resets the backlight on every touch, so a one-off write doesn't stick:
# a small loop puts it back until reboot. One loop at a time (pid in /tmp/op8-dim.pid).
dim_recovery() {
    case "$RECOVERY_BRIGHTNESS" in
        0|off) return ;;
        ''|*[!0-9]*) warn "RECOVERY_BRIGHTNESS should be a percent (got '$RECOVERY_BRIGHTNESS'); leaving the screen alone"; return ;;
    esac
    local out
    out=$(rsh 'B=/sys/class/backlight/panel0-backlight; [ -w $B/brightness ] || exit 0
        P=/tmp/op8-dim.pid; [ -f $P ] && kill $(cat $P) 2>/dev/null
        L=$(( ($(cat $B/max_brightness) * '"$RECOVERY_BRIGHTNESS"' + 50) / 100 )); [ $L -ge 1 ] || L=1
        nohup sh -c "while :; do [ \"\$(cat $B/brightness)\" = $L ] || echo $L > $B/brightness; sleep 0.3; done" >/dev/null 2>&1 &
        echo $! > $P; echo "dimmed=$L"' || true)
    case "$out" in dimmed=*) say "Recovery screen held at $RECOVERY_BRIGHTNESS% brightness until reboot" ;; esac
}

mount_system() {  # $1 = rw|ro
    local dev
    dev=$(rsh "grep ' /mnt/system ' /proc/mounts | cut -d' ' -f1")
    [ -n "$dev" ] || die "system isn't mounted. Tap 'Mount system' in recovery first."
    if [ "$1" = rw ]; then
        rsh "blockdev --setrw $dev; mount -o remount,rw /mnt/system" >/dev/null || true
        rsh "touch $SYS/etc/.rwtest && rm $SYS/etc/.rwtest && echo ok" | grep -q ok \
            || die "couldn't make system writable"
    else
        rsh "sync; mount -o remount,ro /mnt/system" >/dev/null || warn "couldn't remount system read-only (harmless)"
    fi
}

part_dir() {  # $1 = odm|vendor; prints a readable mount of that partition, or nothing
    local p=$1
    if [ "$(rsh "[ -d /mnt/$p/etc ] && echo y")" = y ]; then echo "/mnt/$p"; return; fi
    rsh "mkdir -p /tmp/$p-ro; [ -d /tmp/$p-ro/etc ] || mount -o ro /dev/block/mapper/$p\$(getprop ro.boot.slot_suffix) /tmp/$p-ro" >/dev/null 2>&1 || true
    if [ "$(rsh "[ -d /tmp/$p-ro/etc ] && echo y")" = y ]; then echo "/tmp/$p-ro"; fi
}

cmd_recovery() {
    (cd "$FILES" && sha256sum --quiet -c SHA256SUMS) || die "bundled files are corrupt (checksum mismatch)"
    command -v python3 >/dev/null || die "python3 is needed on this PC"
    need_state recovery
    become_root
    dim_recovery
    mount_system rw
    local odm vendor
    odm=$(part_dir odm)
    [ -n "$odm" ] || die "couldn't mount the odm partition"
    vendor=$(part_dir vendor)
    [ -n "$vendor" ] || warn "couldn't mount vendor; assuming the audio HAL is still 32-bit"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/layer"

    say "ROM: $(rsh getprop ro.crdroid.display.version) ($(rsh getprop ro.product.device))"

    # Dolby: only if the ROM still needs the library and still doesn't ship it.
    if [ "$(rsh "[ -e $odm/lib64/$V33 ] || [ -n '$vendor' -a -e '$vendor/lib64/$V33' ] && echo y")" = y ]; then
        say "Dolby: the ROM ships $V33 now, skipping"
    elif [ "$(rsh "grep -q $V33 $odm/lib64/libdlbdsservice_v3_6.so 2>/dev/null && echo y")" != y ]; then
        say "Dolby: this ROM's Dolby service doesn't need $V33, skipping"
    else
        mkdir -p "$tmp/layer/lib64"
        cp "$FILES/$V33" "$tmp/layer/lib64/"
        say "Dolby: adding $V33"
    fi

    # JamesDSP: the effect must match the audio HAL's bitness; the bundled build is 32-bit.
    local bits=""
    [ -z "$vendor" ] || bits=$(rsh "f=$vendor/bin/hw/android.hardware.audio.service; [ -f \$f ] && head -c 5 \$f | tail -c 1 | od -An -tu1" | tr -d ' ' || true)
    if [ "$bits" = 2 ]; then
        warn "JamesDSP: the audio HAL is 64-bit now; the bundled libjamesdsp.so is 32-bit. Skipping JamesDSP."
    elif [ "$(rsh "[ -f $odm/etc/audio_effects.xml ] && echo y")" != y ]; then
        warn "JamesDSP: $odm/etc/audio_effects.xml is gone in this ROM. Skipping JamesDSP."
    else
        [ "$bits" = 1 ] || warn "JamesDSP: couldn't tell the audio HAL's bitness, assuming 32-bit"
        mkdir -p "$tmp/layer/lib/soundfx" "$tmp/layer/etc"
        cp "$FILES/libjamesdsp.so" "$tmp/layer/lib/soundfx/"
        adb pull "$odm/etc/audio_effects.xml" "$tmp/audio_effects.xml" >/dev/null
        python3 -I - "$tmp/audio_effects.xml" "$tmp/layer/etc/audio_effects.xml" "$JDSP_UUID" <<'EOF'
import sys, xml.dom.minidom
src, dst, uuid = sys.argv[1:]
x = open(src).read()
if 'libjamesdsp.so' not in x:
    assert x.count('<libraries>') == 1 and x.count('<effects>') == 1, 'unexpected audio_effects.xml layout'
    x = x.replace('<libraries>', '<libraries>\n        <library name="jdsp" path="libjamesdsp.so"/>', 1)
    x = x.replace('<effects>', f'<effects>\n        <effect name="jamesdsp" library="jdsp" uuid="{uuid}"/>', 1)
xml.dom.minidom.parseString(x)
open(dst, 'w').write(x)
EOF
        say "JamesDSP: adding libjamesdsp.so and patching audio_effects.xml"
    fi

    # Thermals: run once at boot from the overlay, in thermal-engine's SELinux domain.
    mkdir -p "$tmp/layer/bin"
    cp "$FILES/thermal_tune.sh" "$tmp/layer/bin/"
    say "Thermals: adding skin trip-point tuning"

    # Haptics: only for the vibrator stack it was written for (aw8697 + the oplus QTI HAL).
    local haptics=""
    if [ -z "$vendor" ]; then
        warn "Haptics: couldn't mount vendor to check the ROM's vibrator HAL. Skipping haptics."
    elif [ "$(rsh "[ -f $vendor/$STOCK_VIB ] && [ -e /sys/class/leds/vibrator/waveform_index ] && echo y")" != y ]; then
        warn "Haptics: this ROM's vibrator HAL or driver changed ($STOCK_VIB / leds/vibrator). Skipping haptics."
    else
        mkdir -p "$tmp/layer/bin/hw"
        cp "$FILES/$VIB_BIN" "$tmp/layer/bin/hw/"
        haptics=y
        say "Haptics: adding the vibrator HAL with amplitude control + primitives"
    fi

    # Clear this and older versions of the fix, then write the new layer.
    rsh "rm -rf $LAYER $RC $VIB_RC $SYS/etc/dolbyfix $SYS/etc/init/dolbyfix.rc"
    if [ -z "$(ls -A "$tmp/layer")" ]; then
        say "Nothing to add for this ROM."
        mount_system ro
        return
    fi
    adb push "$tmp/layer" "$LAYER" >/dev/null
    # files/odm_overlay.rc: mounts the layer over /odm at boot and runs the thermal script.
    # Shared with the flashable zip (flashable/), so both install the same file.
    adb push "$FILES/odm_overlay.rc" "$RC" >/dev/null
    [ -z "$haptics" ] || adb push "$FILES/vibrator_op8.rc" "$VIB_RC" >/dev/null
    # Same owners, modes and SELinux labels as the real /odm files.
    rsh "chown -R root:root $LAYER $RC; find $LAYER -type d -exec chmod 755 {} +; find $LAYER -type f -exec chmod 644 {} +; chmod 644 $RC
         chcon -R u:object_r:vendor_file:s0 $LAYER; [ ! -d $LAYER/etc ] || chcon -R u:object_r:vendor_configs_file:s0 $LAYER/etc
         chcon u:object_r:system_file:s0 $RC
         T=$LAYER/bin/thermal_tune.sh; [ ! -f \$T ] || { chmod 755 \$T; chcon u:object_r:vendor_thermal-engine_exec:s0 \$T; }
         V=$LAYER/bin/hw/$VIB_BIN; [ ! -f \$V ] || { chmod 755 \$V; chcon u:object_r:hal_vibrator_default_exec:s0 \$V; }
         [ ! -f $VIB_RC ] || { chown root:root $VIB_RC; chmod 644 $VIB_RC; chcon u:object_r:system_file:s0 $VIB_RC; }"

    # Mount the exact overlay on a scratch dir to prove it works before rebooting.
    local check
    check=$(rsh "M=/tmp/odm-test; mkdir -p \$M
        mount -t overlay overlay -o ro,lowerdir=$LAYER:$odm,override_creds=off \$M || exit
        n=\$(ls \$M | wc -l); echo dirs=\$n
        [ ! -d $LAYER/etc ] || grep -c $JDSP_UUID \$M/etc/audio_effects.xml | sed 's/^/jdsp=/'
        [ -x \$M/bin/thermal_tune.sh ] && echo thermal=ok
        [ ! -f $LAYER/bin/hw/$VIB_BIN ] || { [ -x \$M/bin/hw/$VIB_BIN ] && ls -Z \$M/bin/hw/$VIB_BIN | grep -q hal_vibrator_default_exec && echo haptics=ok || echo haptics=BAD; }
        umount \$M; rmdir \$M" || true)
    if [ -n "$haptics" ] && ! echo "$check" | grep -q '^haptics=ok'; then
        rsh "rm -rf $LAYER $RC $VIB_RC"
        mount_system ro
        die "the vibrator HAL isn't executable with the right SELinux label in the test mount; nothing was left on the phone. Output: $check"
    fi
    echo "$check" | grep -q '^dirs=[1-9]' || {
        rsh "rm -rf $LAYER $RC $VIB_RC"
        mount_system ro
        die "test mount of the overlay failed, nothing was left on the phone. Output: $check"
    }
    rsh "ls -lZR $LAYER $RC $VIB_RC 2>/dev/null" | grep -E '\.so|\.xml|\.rc|\.sh|\.op8' | sed 's/^/    /' || true
    mount_system ro
    say "Overlay written and test-mounted OK."

    local ans
    read -r -p "Reboot into Android now and finish setup? [Y/n] " ans || ans=n
    case "${ans:-y}" in
        [Yy]*) adb reboot; cmd_postboot ;;
        *) say "Later: reboot, then run './apply.sh postboot'." ;;
    esac
}

wait_boot() {
    say "Waiting for Android to finish booting…"
    adb wait-for-device
    for _ in $(seq 1 200); do
        [ "$(rsh getprop sys.boot_completed 2>/dev/null)" = 1 ] && return
        sleep 3
    done
    die "phone didn't finish booting in 10 minutes. Run './apply.sh postboot' once it has."
}

# JamesDSP speaker curve. Without root, adb can't change another app's settings, so this only
# hands the preset over (in Download/) and lists the taps. If JamesDSP already holds this exact
# preset, its settings survived (ROM update) and are left alone.
jdsp_preset() {
    local name want have dl
    name=$(basename "$JDSP_PRESET")
    want=$(sha256sum "$JDSP_PRESET" | cut -d' ' -f1)
    have=$(rsh "sha256sum '$JDSP_PRESETS/$name' 2>/dev/null || true" | cut -d' ' -f1)
    if [ "$have" = "$want" ]; then
        say "JamesDSP: your speaker preset is already in the app; its settings are left as they are"
        return
    fi
    dl=/sdcard/Download/$name
    have=$(rsh "sha256sum '$dl' 2>/dev/null || true" | cut -d' ' -f1)
    if [ -z "$have" ]; then
        adb push "$JDSP_PRESET" "$dl" >/dev/null || true
        have=$(rsh "sha256sum '$dl' 2>/dev/null || true" | cut -d' ' -f1)
    fi
    if [ "$have" != "$want" ]; then
        warn "JamesDSP: Download/$name is missing or isn't the bundled preset (left as it is). Copy $JDSP_PRESET to the phone by hand."
        return
    fi
    say "JamesDSP: speaker preset is in Download/$name. To use it on the phone speaker only:"
    printf '      %s\n' \
        "1. Open JamesDSP and finish its first-run screens." \
        "2. Settings > Device profiles > turn on 'Per-device profiles'." \
        "3. Unplug headphones and disconnect Bluetooth audio, so the main screen's" \
        "   'Active device profile' is the phone speaker." \
        "4. Presets > Import > Download/$name, then tap it to load it." \
        "   Headphones and Bluetooth devices get their own profiles, which start blank."
}

cmd_postboot() {
    wait_boot
    need_state device
    if ! rsh "pm path james.dsp" | grep -q package:; then
        say "Installing JamesDSP (root build)…"
        adb install "$APK" >/dev/null
    fi
    rsh "pm grant james.dsp android.permission.DUMP" || warn "couldn't grant DUMP to JamesDSP"
    rsh "pm grant james.dsp android.permission.POST_NOTIFICATIONS" 2>/dev/null || true
    jdsp_preset
    # Haptics: crDroid's slider toggles. Soft per-step ticks on our HAL; on the ROM's HAL they buzz,
    # so leave them alone there. QS tile haptics stay as they are.
    if [ "$(rsh "pidof $VIB_BIN >/dev/null && echo y")" = y ]; then
        rsh "settings put system qs_brightness_slider_haptic 1; settings put secure volume_dialog_haptic_feedback 1"
        say "Haptics: brightness and volume slider haptics turned on"
    else
        warn "Haptics: the OnePlus 8 vibrator HAL isn't running, so the slider haptics settings were left as they are"
    fi
    cmd_status
}

cmd_status() {
    need_state device
    local ov dms cams jdsp app
    ov=$(rsh "grep -q '^overlay /odm overlay' /proc/mounts && echo active || echo 'NOT active'")
    dms=$(rsh "getprop init.svc.dms-v36-hal-2-0")
    cams=$(rsh "dumpsys media.camera | grep 'Number of camera devices' | grep -o '[0-9]*'" || true)
    app=$(rsh "dumpsys package james.dsp 2>/dev/null | grep -m1 versionName | cut -d= -f2")
    jdsp=$(rsh "dumpsys media.audio_flinger 2>/dev/null | grep -q 'name: JamesDSP' && echo 'loaded in the audio chain' || echo 'not running yet (open the JamesDSP app)'")
    local vib
    vib=$(rsh 'm=$(getprop sys.vibrator.op8.mode); case "$m" in 0) pidof android.hardware.vibrator-service.op8 >/dev/null && echo "OnePlus 8 HAL (running)" || echo "OnePlus 8 HAL (NOT running)";; 1) echo "ROM HAL (switched with persist.debug.vib.stock=1)";; fallback) echo "ROM HAL (FELL BACK: ours crashed, see logcat -s vibrator-op8)";; *) echo "ROM HAL (haptics fix not installed)";; esac')
    local preset want have
    want=$(sha256sum "$JDSP_PRESET" | cut -d' ' -f1)
    have=$(rsh "sha256sum '$JDSP_PRESETS/$(basename "$JDSP_PRESET")' 2>/dev/null || true" | cut -d' ' -f1)
    case "$have" in
        "$want") preset="$(basename "$JDSP_PRESET" .tar) in the app (same as files/jamesdsp)" ;;
        "")      preset="$(basename "$JDSP_PRESET" .tar) not in the app's Presets ('./apply.sh postboot' offers it)" ;;
        *)       preset="$(basename "$JDSP_PRESET" .tar) in the app but DIFFERENT from files/jamesdsp" ;;
    esac
    local sliders
    sliders=$(rsh 'o() { case "$1" in 1) echo on;; 0) echo off;; null|"") echo default;; *) echo "$1";; esac; }
        echo "brightness $(o $(settings get system qs_brightness_slider_haptic)), volume $(o $(settings get secure volume_dialog_haptic_feedback)), QS tiles $(o $(settings get system qs_tile_haptic))"' || true)
    trips=$(rsh 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type); case $t in skin-therm|skin-msm-therm-step) printf "%s:" $t; for f in $z/trip_point_*_temp; do printf " %s" $(($(cat $f)/1000)); done; printf "  ";; esac; done' || true)
    printf '  %-16s %s\n' "/odm overlay:" "$ov" \
        "Dolby service:" "${dms:-not present}" \
        "JamesDSP app:" "${app:-not installed}" \
        "JamesDSP effect:" "$jdsp" \
        "JamesDSP preset:" "$preset" \
        "Skin trips (°C):" "${trips:-?} (stock 46 47 48 50 / 63 65)" \
        "Cameras:" "${cams:-?} (6 expected)" \
        "Vibrator HAL:" "${vib:-?}" \
        "Slider haptics:" "${sliders:-?}"
}

cmd_remove() {
    need_state recovery
    become_root
    dim_recovery
    mount_system rw
    rsh "rm -rf $LAYER $RC $VIB_RC $SYS/etc/dolbyfix $SYS/etc/init/dolbyfix.rc"
    mount_system ro
    say "Removed. Reboot to go back to the stock /odm and the ROM's vibrator HAL. (JamesDSP app left installed.)"
    say "On the ROM's HAL the slider haptics buzz again: turn them off in crDroid's settings if they bother you."
}

case "${1:-}" in
    recovery) cmd_recovery ;;
    postboot) cmd_postboot ;;
    status)   cmd_status ;;
    remove)   cmd_remove ;;
    -h|--help|help) usage 0 ;;
    *) usage 1 ;;
esac

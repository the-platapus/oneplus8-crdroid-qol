#!/usr/bin/env bash
# Runs the zips' installer on this PC against a fake recovery, under dash and busybox sh
# (Android's sh is mksh; these catch the same POSIX mistakes). Fake partitions live in a
# temp dir; mount, umount, chcon, chown, blockdev, getprop and 'ls -Z' are stand-ins that
# keep their state in files. Nothing here talks to a phone.
#   ./build.sh && ./test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP=$(ls "$HERE"/out/oneplus8-fixes-2*.zip | tail -1)
UZIP=$(ls "$HERE"/out/oneplus8-fixes-uninstall-*.zip | tail -1)
FILES="$HERE/../files"
FIX="$HERE/test"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() {
    local d=$1; shift
    if "$@"; then pass=$((pass+1)); printf '  ok    %s\n' "$d"
    else fail=$((fail+1)); printf '  FAIL  %s\n' "$d"; sed 's/^/          | /' "$T/out"; fi
}

# ---- stand-ins ---------------------------------------------------------------
mkdir -p "$T/bin"
cat > "$T/bin/getprop" <<'EOF'
#!/bin/sh
case "$1" in
  ro.boot.slot_suffix) echo _a ;;
  ro.product.device|ro.build.product|ro.product.vendor.device) echo "${FAKE_DEVICE:-OnePlus8}" ;;
  ro.crdroid.display.version) echo v12.9-test ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$T/bin/blockdev"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/chown"
cat > "$T/bin/chcon" <<'EOF'
#!/bin/bash
[ "${FAKE_CHCON_FAIL:-0}" = 1 ] && { echo "chcon: Permission denied" >&2; exit 1; }
rec=0; args=()
for a in "$@"; do case "$a" in -R) rec=1 ;; -h) ;; *) args+=("$a") ;; esac; done
ctx=${args[0]}
for p in "${args[@]:1}"; do
  [ -e "$p" ] || { echo "chcon: $p: No such file" >&2; exit 1; }
  if [ $rec = 1 ]; then find "$p"; else echo "$p"; fi | while read -r q; do
    printf '%s\t%s\n' "$(realpath "$q")" "$ctx" >> "$FAKE_T/labels"
  done
done
EOF
cat > "$T/bin/ls" <<'EOF'
#!/bin/bash
z=0; paths=()
for a in "$@"; do case "$a" in -*Z*) z=1 ;; -*) ;; *) paths+=("$a") ;; esac; done
[ $z = 1 ] || exec /usr/bin/ls "$@"
for p in "${paths[@]}"; do
  [ -e "$p" ] || { echo "ls: $p: No such file" >&2; continue; }
  l=$(grep -F "$(realpath "$p")	" "$FAKE_T/labels" 2>/dev/null | tail -1 | cut -f2)
  echo "${l:-u:object_r:unlabeled:s0} $p"
done
EOF
cat > "$T/bin/mount" <<'EOF'
#!/bin/bash
M=$OP8_ROOT/proc/mounts
if [ "$1" = -o ] && [ "${2%%,*}" = remount ]; then
  dir=$3; mode=${2#remount,}
  grep -q " $dir " "$M" || exit 1
  sed -i "s|^\([^ ]*\) $dir \([^ ]*\) [^ ]*|\1 $dir \2 $mode|" "$M"; exit 0
fi
if [ "$1" = -t ] && [ "$2" = overlay ]; then
  opts=$5; m=$6; lower=${opts#*lowerdir=}; lower=${lower%%,*}; up=${lower%%:*}; low=${lower#*:}
  mkdir -p "$m"; cp -a "$low/." "$m/"; cp -a "$up/." "$m/"
  for src in "$low" "$up"; do
    (cd "$src" && find . -mindepth 1) | while read -r r; do
      l=$(grep -F "$(realpath "$src/$r")	" "$FAKE_T/labels" | tail -1 | cut -f2)
      [ -z "$l" ] || printf '%s\t%s\n' "$(realpath "$m/$r")" "$l" >> "$FAKE_T/labels"
    done
  done
  echo "overlay $m overlay ro 0 0" >> "$M"; exit 0
fi
[ "$1" = -o ] || exit 1
mode=$2; dev=$3; dir=$4
name=$(basename "$dev"); name=${name%_a}
[ -d "$FAKE_T/parts/$name" ] || exit 1
rmdir "$dir" 2>/dev/null || { echo "mount: $dir busy" >&2; exit 1; }
ln -s "$FAKE_T/parts/$name" "$dir"
echo "$dev $dir ext4 $mode 0 0" >> "$M"
EOF
cat > "$T/bin/umount" <<'EOF'
#!/bin/bash
M=$OP8_ROOT/proc/mounts; dir=$1
line=$(grep " $dir " "$M") || exit 1
grep -v " $dir " "$M" > "$M.new"; mv "$M.new" "$M"
case "$line" in
  overlay*) rm -rf "$dir"; mkdir "$dir" ;;
  *) rm "$dir"; mkdir "$dir" ;;
esac
EOF
chmod +x "$T/bin/"*

# ---- a fake phone in recovery --------------------------------------------------
fresh() {  # the ROM as it ships, none of the fixes installed
    R=$T/root; rm -rf "$R" "$T/parts"; : > "$T/labels"
    mkdir -p "$R/proc" "$R/tmp" "$R/mnt/system" "$R/dev/block/mapper" \
             "$R/sys/class/backlight/panel0-backlight" "$R/sys/class/leds/vibrator"
    : > "$R/proc/mounts"
    touch "$R/dev/block/mapper/"{system_a,odm_a,vendor_a} "$R/sys/class/leds/vibrator/waveform_index"
    echo 2047 > "$R/sys/class/backlight/panel0-backlight/max_brightness"
    echo 900 > "$R/sys/class/backlight/panel0-backlight/brightness"
    local P=$T/parts
    mkdir -p "$P/system/system/etc/init" "$P/odm/etc" "$P/odm/lib64" "$P/vendor/bin/hw"
    echo "ro.build.version.sdk=36" > "$P/system/system/build.prop"
    cp "$FIX/audio_effects.orig.xml" "$P/odm/etc/audio_effects.xml"
    printf 'ELF...needs libstagefright_foundation-v33.so...' > "$P/odm/lib64/libdlbdsservice_v3_6.so"
    printf '\x7fELF\x01\x01\x01' > "$P/vendor/bin/hw/android.hardware.audio.service"
    echo stock > "$P/vendor/bin/hw/vendor.qti.hardware.vibrator.service.oplus"
    SYS=$P/system/system
}
run() {  # like recovery: update-binary <api> <outfd> <zip>. $1 = zip, rest = env settings
    local zip=$1; shift
    rm -rf "$T/x"; mkdir -p "$T/x"; unzip -q -o "$zip" META-INF/com/google/android/update-binary -d "$T/x"
    if [ "${SHELLCMD[0]}" = busybox ]; then
        # busybox sh runs its own mount/ls/... before PATH; shell functions come first, so
        # the stand-ins become functions and the installer is sourced with recovery's args.
        cat > "$T/bbwrap.sh" <<EOF
for c in mount umount chcon chown blockdev getprop ls; do eval "\$c() { \"$T/bin/\$c\" \"\\\$@\"; }"; done
set -- 3 1 "$zip"
. "$T/x/META-INF/com/google/android/update-binary"
EOF
        env PATH="$T/bin:$PATH" OP8_ROOT="$R" FAKE_T="$T" "$@" busybox sh "$T/bbwrap.sh" > "$T/out" 2>&1
    else
        env PATH="$T/bin:$PATH" OP8_ROOT="$R" FAKE_T="$T" "$@" \
            "${SHELLCMD[@]}" "$T/x/META-INF/com/google/android/update-binary" 3 1 "$zip" > "$T/out" 2>&1
    fi
    echo $? > "$T/rc"
    sleep 0.5
    cat "$R/sys/class/backlight/panel0-backlight/brightness" > "$T/bright"
    [ ! -f "$R/tmp/op8-dim.pid" ] || kill "$(cat "$R/tmp/op8-dim.pid")" 2>/dev/null
    rm -f "$R/tmp/op8-dim.pid"
}
rc()   { [ "$(cat "$T/rc")" = "$1" ]; }
said() { grep -q -- "$1" "$T/out"; }
both() { rc "$1" && said "$2"; }
lab()  { grep -F "$(realpath "$1")	" "$T/labels" | tail -1 | cut -f2; }
tree_sum() { (cd "$SYS" && { find . -printf '%p %m\n' | sort; find . -type f -exec sha256sum {} + | sort; }) | sha256sum; }
same_tree() { [ "$(tree_sum)" = "$1" ]; }
nothing_mounted() { [ ! -s "$R/proc/mounts" ] && [ -z "$(ls -A "$R/tmp/op8-mnt" 2>/dev/null)" ]; }
gone() { local p; for p; do [ ! -e "$p" ] || return 1; done; }
there_x() { [ -x "$1" ]; }

expected_install() {  # exactly what apply.sh writes: contents, modes, labels
    local L=$SYS/etc/odm_overlay e=0 f rel src mode ctx d rcf
    for f in lib64/libstagefright_foundation-v33.so:libstagefright_foundation-v33.so:644:vendor_file \
             lib/soundfx/libjamesdsp.so:libjamesdsp.so:644:vendor_file \
             bin/thermal_tune.sh:thermal_tune.sh:755:vendor_thermal-engine_exec \
             bin/hw/android.hardware.vibrator-service.op8:android.hardware.vibrator-service.op8:755:hal_vibrator_default_exec; do
        IFS=: read -r rel src mode ctx <<<"$f"
        cmp -s "$L/$rel" "$FILES/$src" || { echo "content $rel"; e=1; }
        [ "$(stat -c %a "$L/$rel")" = "$mode" ] || { echo "mode $rel"; e=1; }
        [ "$(lab "$L/$rel")" = "u:object_r:$ctx:s0" ] || { echo "label $rel: $(lab "$L/$rel")"; e=1; }
    done
    cmp -s "$L/etc/audio_effects.xml" "$FIX/audio_effects.patched.xml" || { echo "audio_effects.xml differs from apply.sh's"; e=1; }
    [ "$(stat -c %a "$L/etc/audio_effects.xml")" = 644 ] && [ "$(lab "$L/etc/audio_effects.xml")" = u:object_r:vendor_configs_file:s0 ] || { echo "xml mode/label"; e=1; }
    for d in "" bin bin/hw lib lib/soundfx lib64; do
        [ "$(stat -c %a "$L/$d")" = 755 ] && [ "$(lab "$L/$d")" = u:object_r:vendor_file:s0 ] || { echo "dir '$d'"; e=1; }
    done
    [ "$(stat -c %a "$L/etc")" = 755 ] && [ "$(lab "$L/etc")" = u:object_r:vendor_configs_file:s0 ] || { echo "dir etc"; e=1; }
    [ "$(find "$L" | wc -l)" = 12 ] || { echo "unexpected entries: $(find "$L" | wc -l)"; e=1; }
    for rcf in odm_overlay.rc vibrator_op8.rc; do
        cmp -s "$SYS/etc/init/$rcf" "$FILES/$rcf" && [ "$(stat -c %a "$SYS/etc/init/$rcf")" = 644 ] \
            && [ "$(lab "$SYS/etc/init/$rcf")" = u:object_r:system_file:s0 ] || { echo "rc $rcf"; e=1; }
    done
    [ $e = 0 ] || echo "expected_install: see above" >> "$T/out"
    return $e
}

for name in dash "busybox sh"; do
    read -r -a SHELLCMD <<<"$name"
    echo "== $name"

    fresh
    run "$ZIP"
    [ -z "${SHOW:-}" ] || sed 's/^/    screen| /' "$T/out"
    check "install: exit 0" rc 0
    check "install: same files, modes and labels as apply.sh" expected_install
    check "install: everything unmounted again" nothing_mounted
    check "install: scratch dir removed" gone "$R/tmp/op8-fixes"
    check "install: recovery screen held at 2% (41/2047)" test "$(cat "$T/bright")" = 41
    installed=$(tree_sum)

    run "$ZIP" OP8_DRY_RUN=1
    [ -z "${SHOW:-}" ] || sed 's/^/    screen| /' "$T/out"
    check "dry run: reports identical" both 0 "Identical to what"
    check "dry run: system untouched" same_tree "$installed"

    run "$ZIP"
    check "reflash: exit 0" rc 0
    check "reflash: identical to the first install" same_tree "$installed"

    echo tweak >> "$SYS/etc/odm_overlay/bin/thermal_tune.sh"
    run "$ZIP" OP8_DRY_RUN=1
    check "dry run: spots a changed file" said "would change: bin/thermal_tune.sh"

    before=$(tree_sum)
    run "$ZIP" FAKE_CHCON_FAIL=1
    check "labels can't be set: refuses" both 1 "system untouched"
    check "labels can't be set: system untouched" same_tree "$before"

    run "$ZIP" FAKE_DEVICE=OnePlus8Pro
    check "wrong device: refuses" both 1 "only for the OnePlus 8"
    check "wrong device: system untouched" same_tree "$before"

    rm -rf "$T/z"; mkdir -p "$T/z/files"; cp "$ZIP" "$T/bad.zip"; echo junk > "$T/z/files/thermal_tune.sh"
    (cd "$T/z" && zip -q "$T/bad.zip" files/thermal_tune.sh)
    run "$T/bad.zip"
    check "damaged payload: refuses" both 1 "damaged file in the zip: files/thermal_tune.sh"
    check "damaged payload: system untouched" same_tree "$before"

    run "$UZIP" OP8_DRY_RUN=1
    check "uninstall dry run: lists what it would remove" both 0 "would remove: etc/odm_overlay"
    check "uninstall dry run: system untouched" same_tree "$before"
    run "$UZIP"
    [ -z "${SHOW:-}" ] || sed 's/^/    screen| /' "$T/out"
    check "uninstall: exit 0" rc 0
    check "uninstall: everything removed" gone "$SYS/etc/odm_overlay" "$SYS/etc/init/odm_overlay.rc" "$SYS/etc/init/vibrator_op8.rc"

    # 'Mount system' tapped in recovery first: use that mount and leave it read-only again.
    fresh
    rmdir "$R/mnt/system"; ln -s "$T/parts/system" "$R/mnt/system"
    echo "$R/dev/block/mapper/system_a $R/mnt/system ext4 ro 0 0" > "$R/proc/mounts"
    run "$ZIP"
    check "system already mounted ro: installs" rc 0
    check "system already mounted ro: same result as apply.sh" expected_install
    check "system already mounted ro: read-only again afterwards" grep -q " $R/mnt/system ext4 ro " "$R/proc/mounts"

    fresh
    printf '\x7fELF\x02\x01\x01' > "$T/parts/vendor/bin/hw/android.hardware.audio.service"
    run "$ZIP"
    check "64-bit audio HAL: JamesDSP skipped with a note" both 0 "64-bit"
    check "64-bit audio HAL: no effect files" gone "$SYS/etc/odm_overlay/etc" "$SYS/etc/odm_overlay/lib"
    check "64-bit audio HAL: haptics still installed" there_x "$SYS/etc/odm_overlay/bin/hw/android.hardware.vibrator-service.op8"

    fresh
    head -c -1 "$FIX/audio_effects.orig.xml" > "$T/parts/odm/etc/audio_effects.xml"
    run "$ZIP"
    check "effects file without final newline: byte-exact edit" cmp -s "$SYS/etc/odm_overlay/etc/audio_effects.xml" <(head -c -1 "$FIX/audio_effects.patched.xml")

    fresh
    touch "$T/parts/odm/lib64/libstagefright_foundation-v33.so"
    rm "$T/parts/vendor/bin/hw/vendor.qti.hardware.vibrator.service.oplus"
    run "$ZIP"
    check "ROM changed: exit 0" rc 0
    check "ROM changed: Dolby and haptics skipped" gone "$SYS/etc/odm_overlay/lib64" "$SYS/etc/odm_overlay/bin/hw" "$SYS/etc/init/vibrator_op8.rc"
    check "ROM changed: thermals still installed" there_x "$SYS/etc/odm_overlay/bin/thermal_tune.sh"
done

echo
echo "$pass passed, $fail failed"
[ $fail = 0 ]

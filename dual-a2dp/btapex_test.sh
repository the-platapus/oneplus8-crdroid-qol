#!/usr/bin/env bash
# Tests btapex.sh against a fake recovery (fake adb, fake /mnt/system, label db). No phone involved.
W="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin $T/root/mnt/system/system/apex $T/root/proc $T/root/sys/class/backlight/panel0-backlight $T/stubs
cat > $T/bin/adb <<'EOF'
#!/bin/bash
rw() { local s=$1; s=${s//\/mnt\/system/$FAKE/root/mnt/system}; s=${s//\/proc\/mounts/$FAKE/root/proc/mounts}; s=${s//\/sys\/class/$FAKE/root/sys/class}; s=${s//\/tmp\/op8-dim.pid/$FAKE/dim.pid}; echo "$s"; }
case "$1" in
  get-state) echo "${FAKE_STATE:-recovery}" ;;
  root) ;;
  shell) shift; PATH="$FAKE/stubs:$PATH" sh -c "$(rw "$*")" ;;
  push) cp "$2" "$(rw "$3")"; [ -n "${FAKE_CORRUPT:-}" ] && printf 'X' | dd of="$(rw "$3")" bs=1 seek=100 conv=notrunc 2>/dev/null; true ;;
esac
EOF
printf '#!/bin/sh\necho 0\n' > $T/stubs/id; printf '#!/bin/sh\nexit 0\n' > $T/stubs/blockdev; printf '#!/bin/sh\nexit 0\n' > $T/stubs/chown
printf '#!/bin/sh\ncase "$*" in *remount*) exit 0;; esac\nexec /usr/bin/mount "$@"\n' > $T/stubs/mount
printf '#!/bin/sh\necho "$2 $1" >> "$FAKE/labels"\n' > $T/stubs/chcon
cat > $T/stubs/ls <<'EOF'
#!/bin/sh
if [ "$1" = -Z ]; then l=$(grep -F "$2 " "$FAKE/labels" | tail -1 | cut -d' ' -f2); echo "${l:-u:object_r:unlabeled:s0} $2"; else exec /usr/bin/ls "$@"; fi
EOF
chmod +x $T/bin/adb $T/stubs/*
echo 2047 > $T/root/sys/class/backlight/panel0-backlight/max_brightness; echo 900 > $T/root/sys/class/backlight/panel0-backlight/brightness
C=$T/root/mnt/system/system/apex/com.android.bt.capex
reset() { cp $W/apex/com.android.bt.capex $C; touch -d '2009-01-01 05:00' $C; echo "$C u:object_r:system_file:s0" > $T/labels
          echo "/dev/block/dm-0 $T/root/mnt/system ext4 ro 0 0" > $T/root/proc/mounts; }
name() { local s; s=$(sha256sum $C | cut -d' ' -f1)
  for k in original:$W/apex/com.android.bt.capex unchanged:$W/out/unchanged/com.android.bt.capex patched:$W/out/patched/com.android.bt.capex; do
    [ "$(sha256sum ${k#*:} | cut -d' ' -f1)" = "$s" ] && { echo ${k%%:*}; return; }; done; echo other; }
label() { grep -F "$C " $T/labels | tail -1 | cut -d' ' -f2; }
go() { (export FAKE=$T PATH=$T/bin:$PATH; "$W/btapex.sh" "$@") >$T/out 2>&1; echo $?; }
killdim() { [ -f $T/dim.pid ] && kill $(cat $T/dim.pid) 2>/dev/null; rm -f $T/dim.pid; }
pass=0; fail=0
t() { if eval "$2"; then pass=$((pass+1)); echo "  ok    $1"; else fail=$((fail+1)); echo "  FAIL  $1"; sed 's/^/        | /' $T/out; fi; }
reset; r=$(go install unchanged); killdim
t "original -> unchanged (label and date kept, no leftovers)" '[ $r = 0 ] && [ $(name) = unchanged ] && [ "$(label)" = u:object_r:system_file:s0 ] && [ "$(stat -c %Y $C)" = "$(date -d "2009-01-01 05:00" +%s)" ] && [ ! -e $C.new ]'
r=$(go install patched); killdim; t "unchanged -> patched" '[ $r = 0 ] && [ $(name) = patched ] && [ "$(label)" = u:object_r:system_file:s0 ]'
r=$(go install patched); killdim; t "patched again: nothing to do" '[ $r = 0 ] && grep -q "nothing to do" $T/out && [ $(name) = patched ]'
r=$(go restore); killdim; t "restore -> crDroid original" '[ $r = 0 ] && [ $(name) = original ]'
reset; echo junk >> $C; r=$(go install patched); killdim; t "unknown module: refused, untouched" '[ $r != 0 ] && grep -q refusing $T/out && [ $(name) = other ]'
reset; r=$(FAKE_CORRUPT=1 go install patched); killdim; t "damaged upload: refused, original kept, no .new" '[ $r != 0 ] && grep -q "upload damaged" $T/out && [ $(name) = original ] && [ ! -e $C.new ]'
reset; r=$(FAKE_STATE=device go install patched); t "not in recovery: refused" '[ $r != 0 ] && [ $(name) = original ]'
reset; : > $T/root/proc/mounts; r=$(go install patched); killdim; t "system not mounted: refused" '[ $r != 0 ] && grep -q "Mount system" $T/out && [ $(name) = original ]'
r=$(go install foo); t "bad argument: usage" '[ $r != 0 ]'
echo "$pass passed, $fail failed"; [ $fail = 0 ]

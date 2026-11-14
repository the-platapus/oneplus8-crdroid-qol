#!/usr/bin/env bash
# Builds the flashable zips from ../files and update-binary:
#   out/oneplus8-fixes-<date>.zip            installs the fixes (same files as apply.sh)
#   out/oneplus8-fixes-uninstall-<date>.zip  removes them (same as './apply.sh remove')
# Flash in crDroid recovery: Apply update > Apply from ADB, then on the PC
#   adb sideload out/oneplus8-fixes-<date>.zip
# The zips are unsigned, so recovery asks "Signature verification failed. Install anyway?": Yes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$HERE/../files"
OUT="$HERE/out"
VER=${VER:-$(date +%Y%m%d)}
PAYLOAD=(libstagefright_foundation-v33.so libjamesdsp.so thermal_tune.sh
         android.hardware.vibrator-service.op8 vibrator_op8.rc odm_overlay.rc)
PRESET=jamesdsp/Oneplus_8_speakers.tar

(cd "$FILES" && sha256sum --quiet -c SHA256SUMS) || { echo "files/ doesn't match files/SHA256SUMS" >&2; exit 1; }
sh -n "$HERE/update-binary"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
stage() {  # $1 = install|uninstall, $2 = staging dir
    local d=$2
    mkdir -p "$d/META-INF/com/google/android"
    sed "s/^MODE=install\$/MODE=$1/" "$HERE/update-binary" > "$d/META-INF/com/google/android/update-binary"
    grep -q "^MODE=$1\$" "$d/META-INF/com/google/android/update-binary"
    echo '# dummy: the installer is update-binary (a shell script)' > "$d/META-INF/com/google/android/updater-script"
    [ "$1" = install ] || return 0
    mkdir -p "$d/files" "$d/jamesdsp"
    for f in "${PAYLOAD[@]}"; do cp "$FILES/$f" "$d/files/"; done
    # Your JamesDSP speaker curve rides along (recovery can't apply app settings; see JAMESDSP.md).
    cp "$FILES/$PRESET" "$d/jamesdsp/"
    cp "$HERE/../JAMESDSP.md" "$d/jamesdsp/"
    (cd "$d" && find files jamesdsp -type f | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
}

mkdir -p "$OUT"
for mode in install uninstall; do
    name=oneplus8-fixes-$VER.zip
    [ "$mode" = install ] || name=oneplus8-fixes-uninstall-$VER.zip
    d=$tmp/$mode
    stage "$mode" "$d"
    # Fixed timestamps and order, so the same inputs give the same zip.
    find "$d" -exec touch -h -d "${VER:0:4}-${VER:4:2}-${VER:6:2} 00:00:00" {} +
    rm -f "$OUT/$name"
    (cd "$d" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q -9 "$OUT/$name" -@)
    echo "$OUT/$name"
    unzip -l "$OUT/$name" | sed -n '4,$p' | sed '$d' | sed '$d' | awk '{printf "    %10s  %s\n", $1, $4}'
done
(cd "$OUT" && sha256sum oneplus8-fixes-*"$VER".zip > "SHA256SUMS-$VER")

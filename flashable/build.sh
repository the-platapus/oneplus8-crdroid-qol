#!/usr/bin/env bash
# Builds the flashable zips from ../files and update-binary:
#   out/oneplus8-fixes-<ver>.zip             installs the fixes (same files as apply.sh)
#   out/oneplus8-fixes-uninstall-<ver>.zip   removes them (same as './apply.sh remove')
#   out/SHA256SUMS-<ver>
# <ver> is VER from the environment, else today's date (YYYYMMDD).
# Flash in crDroid recovery: Apply update > Apply from ADB, then on the PC
#   adb sideload out/oneplus8-fixes-<ver>.zip
# The zips are unsigned, so recovery asks "Signature verification failed. Install anyway?": Yes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$HERE/../files"
OUT="$HERE/out"
VER=${VER:-$(date +%Y%m%d)}     # CI sets it from the release tag (v20261114 -> 20261114)
[[ "$VER" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "VER '$VER' isn't a plain version string" >&2; exit 1; }
# File times inside the zips: the last commit's time (or SOURCE_DATE_EPOCH), so a commit always
# builds byte-identical zips, locally or in CI.
STAMP=${SOURCE_DATE_EPOCH:-$(git -C "$HERE" log -1 --format=%ct 2>/dev/null || date +%s)}
export TZ=UTC
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
    # Fixed modes, timestamps and order, so the same inputs give the same zip on any machine.
    find "$d" -type d -exec chmod 755 {} +
    find "$d" -type f -exec chmod 644 {} +
    chmod 755 "$d/META-INF/com/google/android/update-binary"
    find "$d" -exec touch -h -d "@$STAMP" {} +
    rm -f "$OUT/$name"
    (cd "$d" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q -9 "$OUT/$name" -@)
    echo "$OUT/$name"
    unzip -l "$OUT/$name" | sed -n '4,$p' | sed '$d' | sed '$d' | awk '{printf "    %10s  %s\n", $1, $4}'
done
(cd "$OUT" && sha256sum "oneplus8-fixes-$VER.zip" "oneplus8-fixes-uninstall-$VER.zip" > "SHA256SUMS-$VER")

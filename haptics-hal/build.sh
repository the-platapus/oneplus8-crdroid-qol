#!/usr/bin/env bash
# Builds android.hardware.vibrator-service.op8 (arm64) with the Android NDK.
# Uses the Android 16 binder NDK headers in third_party/binder_ndk_a16 (they match build-tools
# 36 aidl output; NDK 27 ships older ones). Needs: NDK (ANDROID_NDK or ~/Android/Sdk/ndk/*), build-tools 'aidl', and the phone's
# /system/lib64/libbinder_ndk.so + liblog.so to link against (pulled over adb if missing).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NDK="${ANDROID_NDK:-$(ls -d "$HOME"/Android/Sdk/ndk/* | sort -V | tail -1)}"
AIDL="${AIDL:-$(ls -d "$HOME"/Android/Sdk/build-tools/* | sort -V | tail -1)/aidl}"
API=35
CXX="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
OUT="$HERE/out"
GEN="$OUT/gen"
rm -rf "$GEN"; mkdir -p "$GEN/include" "$GEN/src" "$OUT/devlibs"

for l in libbinder_ndk.so liblog.so; do
    [ -f "$OUT/devlibs/$l" ] || adb pull "/system/lib64/$l" "$OUT/devlibs/$l" >/dev/null
done

# Frozen android.hardware.vibrator V2 (Android 12+), NDK backend, VINTF stability.
for f in "$HERE"/third_party/aidl/android/hardware/vibrator/*.aidl; do
    "$AIDL" --lang=ndk --structured --stability=vintf --version=2 \
        --hash="$(tr -d '[:space:]' < "$HERE/third_party/aidl/v2.hash")" \
        --min_sdk_version=$API -I "$HERE/third_party/aidl" \
        -h "$GEN/include" -o "$GEN/src" "$f"
done

"$CXX" --target=aarch64-linux-android$API -std=c++20 -O2 -Wall -Wno-unused-parameter \
    -fPIE -pie -DBINDER_STABILITY_SUPPORT \
    -I "$HERE" -I "$GEN/include" -I "$HERE/third_party/binder_ndk_a16" -I "$HERE/third_party/include" -D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__ \
    "$HERE/Vibrator.cpp" "$HERE/service.cpp" $(find "$GEN/src" -name '*.cpp') \
    -static-libstdc++ -L "$OUT/devlibs" -lbinder_ndk -llog \
    -Wl,--as-needed -Wl,--build-id=sha1 -Wl,-z,max-page-size=4096 -s \
    -o "$OUT/android.hardware.vibrator-service.op8"
ls -la "$OUT/android.hardware.vibrator-service.op8"

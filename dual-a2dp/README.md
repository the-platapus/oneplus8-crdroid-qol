# Dual Bluetooth audio (experimental)

Plays the phone's audio on **two Bluetooth headphones at once**. crDroid 16 can keep several headphones connected, but it only sends audio to the active one. This patch makes it send audio to every connected pair.

> [!WARNING]
> **Not tried on a phone yet.** The patch passes its tests in an ARM64 emulator, and both modules pass the checks Android runs on them at boot. Nothing has been installed on a real phone so far. Step 2 below installs crDroid's own module, only re-signed, to prove the install route before the patch goes on.

It only works on the OnePlus 8 running crDroid `v12.9-20260424`. `btapex.sh` checks the phone's Bluetooth module first and refuses any other build.

## Why classic Bluetooth and not LE Audio

The OnePlus 8's Bluetooth chip has no isochronous channels (LE feature mask `0x0f81fdff`). Without them, LE Audio, Auracast and Android's Audio Sharing can't work. Classic A2DP can do it. The stack already has code that copies every encoded audio packet to a second headset (`bta_av_dup_audio_buf`). The layer above it only ever starts the active headset, so that code never runs. The patch removes that limit.

## Install

You need `bash`, `adb` and the phone connected to the PC. This was tested on Linux. It's written to also run on macOS and in Git Bash on Windows, but neither has been tried.

```bash
git clone -b dual-a2dp https://github.com/the-platapus/oneplus8-crdroid-qol
cd oneplus8-crdroid-qol/dual-a2dp
sha256sum -c SHA256SUMS      # macOS: shasum -a 256 -c SHA256SUMS
```

1. **Check the baseline.** Boot normally with USB debugging on and run `./btapex.sh status`. It should show `Module: original`.
2. **Prove the install route.** Boot to recovery and tap **Mount system** and **Advanced › Enable ADB**. Run `./btapex.sh install unchanged`, then reboot. The first boot unpacks the module again, so it takes a few seconds longer. Bluetooth must work exactly as before, and `status` must show `unchanged`. If it doesn't, go back to recovery and run `./btapex.sh restore`.
3. **Install the patch.** In recovery, run `./btapex.sh install patched` and reboot.
4. **Turn off hardware offload.** In Developer options, turn on **Disable Bluetooth A2DP hardware offload**, then reboot. Offloaded audio goes straight to the Bluetooth chip and never reaches the code that copies it.
5. **Turn off HD audio.** Do this in the Bluetooth settings of both headphones. The copied packets use the active headphones' codec, so both must use plain SBC.
6. **Listen.** Connect both pairs, play something and listen on both. `./btapex.sh status` should list both as streaming.

If only the active pair plays, swap which pair is active. The copies are sized for the active pair, so the pair with the smaller packet size (MTU) has to be the active one.

| | |
|---|---|
| Turn it off until the next reboot | `adb shell setprop debug.bt.dual_a2dp false` |
| Undo everything | In recovery, run `./btapex.sh restore`, then turn A2DP offload back on |
| Phone doesn't finish booting | In recovery, run `./btapex.sh restore` (recovery doesn't use this module) |
| After a ROM update | The update puts crDroid's module back. A new crDroid build needs the patch redone, because the addresses change |

## How it works

The patch changes two places in `/lib64/libbluetooth_jni.so` inside the `com.android.bt` module (version 361099999):

- **`btif_av_stream_start_with_latency` (`0x61beb0`).** Its first instruction now jumps to 247 bytes of new code ([`cave.S`](cave.S)). The new code sits in zero padding after the code segment, at `0xdf1e80`. It takes the peers lock, sends a start request to every other headset that is connected but not yet streaming, and unlocks. It then runs the original function, which starts the active headset as before.
- **The start handler in the Opened state (`0x616acc`).** A check that suspended any non-active headset as soon as it started is now a `nop`. A start that the headset asks for by itself is still suspended.

Nothing else changes. The stack's own copying path encodes the audio once and copies each packet to every started headset. Stop and suspend already applied to every started headset.

The new code does nothing if `debug.bt.dual_a2dp` is set to anything other than `true`. When the property is unset, the patch is on.

## Tests

- **[`harness.c`](harness.c)** runs the real patched bytes on an ARM64 CPU under `qemu-aarch64`. It replaces the lock, unlock, dispatch and property calls with stubs and rebuilds the peer list by hand across 15 scenarios. It checks which headsets get a start request, the shadow call stack, the callee-saved registers and that the lock is always released. **304 checks pass.** Five deliberately broken builds were each caught.
- **[`validate.py`](validate.py)** checks a rebuilt module the way Android does at boot:
  - the signatures, the bundled key and the version;
  - that the recorded digest matches the real one, and the hashtree;
  - the filesystem: `e2fsck` passes, and nothing changed except the library's own blocks.

  `unchanged` passes 20/20 and `patched` passes 22/22. A copy with a tampered digest fails.
- **[`btapex_test.sh`](btapex_test.sh)** runs `btapex.sh` against a fake recovery (Linux only). It covers install, restore, "already installed", an unknown module, a damaged upload, not being in recovery and system not mounted. **9/9 pass.**

## Files

| File | What it is |
|---|---|
| `btapex.sh` | Installs, restores and shows status |
| `apex/com.android.bt.capex` | crDroid's original module, used by `restore` |
| `out/unchanged/com.android.bt.capex` | crDroid's module, re-signed with this project's key |
| `out/patched/com.android.bt.capex` | The same, with the patched library |
| `cave.S`, `build_patch.sh` | The patch, and the script that applies it to the library |
| `payload_extract.py` | Pulls one partition image out of a crDroid OTA zip (standard library only) |
| `repack.py`, `validate.py` | Rebuild a module with your own keys, and check it |
| `harness.c`, `btapex_test.sh`, `dis.py` | Tests and a disassembly helper |

## Rebuilding

The modules are signed with a private key that isn't in this repo. To rebuild, you need:

- `keys/apex_payload.pem` (RSA-4096), plus `keys/container.pk8` and `keys/container.x509.pem`;
- `src/avbtool.py` from AOSP `external/avb`;
- the NDK r27 LLVM `bin` folder path in `apex/tools.path`;
- the build-tools path (`apksigner`, `zipalign`) in `apex/buildtools.path`;
- `debugfs` and `e2fsck`.

```bash
unzip -p apex/com.android.bt.capex original_apex > /tmp/oa && unzip -p /tmp/oa apex_payload.img > /tmp/payload.img
debugfs -R 'dump /lib64/libbluetooth_jni.so apex/libbluetooth_jni.so' /tmp/payload.img   # sha256 e3a3b341…
./build_patch.sh                                                            # libbluetooth_jni.so.patched, sha256 3cec9fbd…
python3 -I repack.py apex/com.android.bt.capex - out/unchanged
python3 -I repack.py apex/com.android.bt.capex libbluetooth_jni.so.patched out/patched
python3 -I validate.py apex/com.android.bt.capex out/patched/com.android.bt.capex libbluetooth_jni.so.patched
```

`btapex.sh` recognises modules by hashing the files in `out/`, so rebuilt ones work as they are. Run `sha256sum ... > SHA256SUMS` again, though, because new keys give new signatures and so new hashes. Two outputs always come out the same: the patched library, and the unchanged payload's root digest (`f35548b4…`, crDroid's own).

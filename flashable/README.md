# Flashable zips

Recovery-flashable versions of `../apply.sh recovery` and `../apply.sh remove`, for crDroid 16 on the OnePlus 8.

| Zip | Does |
|---|---|
| `out/oneplus8-fixes-<date>.zip` | Installs the Dolby library, JamesDSP effect + `audio_effects.xml` entry, thermal trip points and haptics HAL. Same files, owners, modes and SELinux labels as `apply.sh`. |
| `out/oneplus8-fixes-uninstall-<date>.zip` | Removes them, like `./apply.sh remove`. |

`out/SHA256SUMS-<date>` holds the checksums of both zips. Ready-made zips are on the
[Releases](https://github.com/the-platapus/oneplus8-crdroid-qol/releases) page: CI builds, tests and publishes
them for every `v<YYYYMMDD>` tag (`.github/workflows/flashable.yml`). Builds are reproducible: the same
commit gives byte-identical zips.

## Flashing

1. Boot to recovery. Tap **Apply update > Apply from ADB**.
2. On the PC:
   ```bash
   adb sideload out/oneplus8-fixes-20261114.zip
   ```
3. Recovery asks "Signature verification failed. Install anyway?". Answer **Yes**: the zip isn't signed with a
   ROM key.
4. Reboot.

If you just flashed a ROM in the same recovery session, reboot to recovery first, as recovery itself asks.
Otherwise the zip changes the old slot, not the one you'll boot.

While it runs, the zip holds the recovery screen at 2% brightness until reboot.

## What the zip can't do

It can't set app-side things: the JamesDSP app, its speaker preset and the slider haptics settings. In recovery
`/data` is encrypted and Android isn't running. A ROM update keeps all of these anyway. After a clean flash, run
`../apply.sh postboot` from the PC.

Your speaker curve still rides along inside the zip, in `jamesdsp/`: the preset plus `JAMESDSP.md` with every
value written out.

## How it stays safe

- It runs only on a OnePlus 8 (`OnePlus8` or `instantnoodle`). It checks the zip's own checksums first.
- It skips each part on its own when the ROM changes. Dolby is skipped if the ROM ships the library, JamesDSP if
  the audio HAL turns 64-bit, haptics if the vibrator HAL or driver changes. Same rules as `apply.sh`.
- Everything is built, labelled and test-mounted over `/odm` in recovery's `/tmp` (RAM) first. If anything is
  off (a label that won't stick, a failed test mount, a damaged file), it stops before touching `/system`.
- After writing to `/system` it checks labels and test-mounts again. If that fails, it removes the fix files.
- It unmounts what it mounted. If you had tapped "Mount system", that mount goes back to read-only.
- Log: `/tmp/op8-fixes.log` in recovery.

crDroid's recovery is a userdebug build, and on those LineageOS's recovery runs its own SELinux domain in
permissive mode. That's what lets a flashed zip set the vendor labels these files need. If a future recovery
ever forbids it, the zip stops at the first check with "labels didn't stick (in /tmp; system untouched)". Use
`apply.sh` then.

## Dry run (writes nothing to the phone's storage)

In recovery with ADB on (Advanced > Enable ADB):

```bash
adb root
```
```bash
adb push out/oneplus8-fixes-20261114.zip /tmp/op8.zip
```
```bash
adb shell 'cd /tmp && unzip -o op8.zip META-INF/com/google/android/update-binary >/dev/null && OP8_DRY_RUN=1 sh META-INF/com/google/android/update-binary 3 1 /tmp/op8.zip'
```

It mounts system read-only, builds and test-mounts everything in `/tmp`, and compares the result with what's
installed (contents, labels, modes). On a phone set up by `apply.sh` it should print "Identical to what's
installed now." Recovery's `/tmp` is RAM, so nothing persists.

## Rebuilding and testing

```bash
./build.sh
```
```bash
./test.sh
```

`build.sh` takes the files from `../files` (checked against `../files/SHA256SUMS`) and `update-binary`.
`test.sh` runs the installer under mksh (Android's own shell), dash and busybox sh against a fake recovery
on the PC. It skips any of those shells that isn't installed; CI runs all three. The fake recovery
has fake partitions, plus stand-ins for mount, chcon, getprop and `ls -Z`. The tests cover these cases:

- install, reflash and dry run
- uninstall
- a label that won't stick, a damaged zip and the wrong device
- "Mount system" already tapped
- a 64-bit audio HAL and a changed ROM
- byte-exact `audio_effects.xml` edits

The fixtures in `test/` come from the phone's own `audio_effects.xml`: the original, and the file `apply.sh`
produced from it.

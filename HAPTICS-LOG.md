# OnePlus 8 haptics work log

Device: OnePlus 8 (IN2015, instantnoodle), crDroid 16.0, build BP4A.251205.006, unrooted.
Started 2026-11-12. Every change to the phone goes here with how to undo it.

## Baseline (2026-11-12, before any change)

Settings (as read with `settings list`):

| namespace | key | value | meaning |
|---|---|---|---|
| system | haptic_feedback_enabled | 1 | touch feedback on |
| system | haptic_feedback_intensity | 2 | touch = medium |
| system | hardware_haptic_feedback_intensity | 2 | |
| system | qs_brightness_slider_haptic | 0 | crDroid: brightness slider haptics OFF (turned off by you) |
| system | qs_tile_haptic | 0 | crDroid: QS tile haptics OFF (turned off by you) |
| secure | volume_dialog_haptic_feedback | 0 | crDroid: volume slider haptics OFF (turned off by you) |
| secure | back_gesture_haptic | 1 | |
| system | keyboard_vibration_enabled | 1 | |

Vibrator stack:
- HAL: `vendor.qti.hardware.vibrator.service.oplus` (source: crdroidandroid/android_hardware_oplus, branch 16.0,
  `aidl/vibrator/qti/Vibrator.cpp`), LED mode via `/sys/class/leds/vibrator`.
- Kernel driver: `aw8697_haptic` (i2c 6-005a), source `drivers/misc/aw8697_haptic/aw8697.c` in
  crdroidandroid/android_kernel_oneplus_sm8250 (16.0-instantnoodle).
- HAL capabilities: ON_CALLBACK, PERFORM_CALLBACK only. No amplitude control, no primitives.
- SystemUI `msdl_feedback` flag is READ_ONLY (compiled in); cannot be turned off without root.

## Findings

- Notification swipe plays MSDL's fallback waveform `10ms@4% 20ms@12% 20ms@20% 10ms@4%` every ~66 ms.
  Without amplitude control Android merges it into `on(60ms)`, and the HAL drives any `on()` > 20 ms at
  full strength (vmax 1600). Result: full-power 60 ms buzz ~15x per second.
- HAL `on(t)`: t <= 20 ms -> vmax = t*10 (gentle); t > 20 ms -> vmax 1600 (full).
- HAL prebaked: CLICK = waveform 1 @ vmax 2500, TICK = waveform 1 @ 1400, TEXTURE_TICK = waveform 2 @ 60,
  HEAVY_CLICK = waveform 4 @ 2500, DOUBLE_CLICK = 2x CLICK.
- Driver `vmax` node: value <= 255 sets gain = value*COMP_GAIN/255 (live amplitude); 800..2400 picks
  boost-voltage/gain table entries; > 2400 = max.
- Gboard's vibration-strength slider: CLOCK_TICK -> TEXTURE_TICK on every step, each cut short by the next.
  You like it: one tick per step, rate follows the finger.
- Feel test: 21 ms oneshot (full power) = buzzy. Low-strength 10 ms pulses ("Y") = close to OnePlus 9 feel.

## Design (2026-11-12)

Replacement vibrator HAL, `haptics-hal/` (built with `haptics-hal/build.sh`, NDK 27 + build-tools 36 aidl,
frozen android.hardware.vibrator V2). Same service name/user/groups as the ROM's, same sysfs writes for the
prebaked effects (CLICK, DOUBLE_CLICK, TICK, HEAVY_CLICK, TEXTURE_TICK stay identical), plus:

- Amplitude control: gain through the driver's vmax node (<= 255). Android's soft waveform steps now play soft.
- Primitives CLICK, TICK (HAL LIGHT_TICK), LOW_TICK, THUD from the chip's RAM waveforms, gain from the scale.
  SystemUI (MSDL) then uses its designed ticks: notification swipe = LOW_TICK x0.3, sliders = LOW_TICK per
  1.5% of travel (continuous) or TICK x0.5 per step (discrete), swipe threshold = CLICK x0.7.
- Unchanged by design: Gboard slider (CLOCK_TICK -> TEXTURE_TICK), keyboard (CLICK), back-gesture trigger
  (TICK). Back-gesture release becomes TICK primitive x0.4 instead of TEXTURE_TICK.
- Live tuning without reflashing: `adb shell setprop debug.vib.<click|tick|lowtick|thud> "wf,level,gmin,gmax,gamma"`,
  `debug.vib.amp "gmax,gamma,short_ms"`, `debug.vib.log 1` (logcat tag `vibrator-op8`). debug.* props reset on reboot.

Safety: `/system/etc/init/vibrator_op8.rc` defines `vendor.qti.vibrator` (parsed before /vendor, so the ROM's
definition is ignored) and keeps the ROM binary as `vendor.qti.vibrator.stock`. If ours crashes or exits,
init switches to the stock one by itself (`sys.vibrator.op8.mode=fallback`). Manual switch back to stock:
`adb shell setprop persist.debug.vib.stock 1` + reboot (`0` + reboot to return). Full undo: `./apply.sh remove`
in recovery.

## Changes

| when | what | undo |
|---|---|---|
| 2026-11-12 | PC only: added `haptics-hal/` (source, build script, rc), bundled `files/android.hardware.vibrator-service.op8` + `files/vibrator_op8.rc`, regenerated `files/SHA256SUMS`, taught `apply.sh` to install/remove/report the HAL. Backup of the previous apply.sh not kept in this folder (it only gained a Haptics section). | - |
| 2026-11-12 | Phone: test vibrations only (cmd vibrator_manager, sysfs ticks in recovery), recovery backlight set to 41/2047 for that session. No persistent change. | - |
| 2026-11-12 | Phone (recovery, `./apply.sh recovery`): overlay rewritten with the existing Dolby/JamesDSP/thermal files plus `/odm/bin/hw/android.hardware.vibrator-service.op8` (label hal_vibrator_default_exec); added `/system/etc/init/vibrator_op8.rc`. After reboot: our HAL runs, Android reports caps ON_CALLBACK, PERFORM_CALLBACK, COMPOSE_EFFECTS, AMPLITUDE_CONTROL; primitives CLICK/THUD/TICK 14 ms, LOW_TICK 12 ms. | `./apply.sh remove` in recovery (removes all overlay fixes), or `setprop persist.debug.vib.stock 1` + reboot (ROM HAL only) |
| 2026-11-12 | Notification swipe test on build 1: soft ticks, "far better". Felt batches of ~3 ticks per step when sliding very slowly: SystemUI sends 5 LOW_TICKs back to back per step, each took ~37 ms to fire (stock tail "stop" busy-waits for the waveform + my extra sleep). | build 2: coalesce + no tail wait |
| 2026-11-12 | Settings: `system qs_brightness_slider_haptic` and `secure volume_dialog_haptic_feedback` set to 1. You had already turned both on yourself during the session, so this was a no-op. | `settings put system qs_brightness_slider_haptic 0`; `settings put secure volume_dialog_haptic_feedback 0` |
| 2026-11-12 | Slider test on build 1: both sliders send 5 x LOW_TICK per step; brightness scales ~0.2-0.4 (softer, preferred), volume ~0.5-0.77 (harder). | - |
| 2026-11-12 | PC: build 2. Runs of identical zero-delay primitives play once (`debug.vib.coalesce`, default on); primitives no longer end with the stock busy-wait stop (`debug.vib.tailstop`, default off); LOW_TICK curve flattened to gain 20..42 linear (was 18..60, gamma 0.7). Prebaked effects unchanged. | rebuild with old defaults, or set the props |
| 2026-11-12 | Phone: build 2 installed (`./apply.sh recovery`). Test: batches gone, strength "just right", but fast slider drags too sparse. Unlock, back gesture, long-press fine. Fast Gboard typing skips clicks: the HAL reports every prebaked effect as 150 ms (stock magic value), and Android waits that out before the next one, so typing got ~5 clicks/s. Same cadence is visible in the stock-era history. | - |
| 2026-11-12 | PC: build 3. Prebaked effects report their real length, 20 ms (`debug.vib.perform_ms`, 150 = stock); LOW_TICK reported as 4 ms so SystemUI may tick up to ~50/s (was 12 ms -> ~16/s). Waveforms unchanged. | `setprop debug.vib.perform_ms 150` (live); LOW_TICK report needs a rebuild |
| 2026-11-12 | Phone: build 3 installed (`./apply.sh recovery`). Test: fast typing keeps up, fast slider drags follow the finger, Gboard vibration-strength slider unchanged ("still perfect"). Checks: no SELinux denials for hal_vibrator_default, 0 CPU over 10 s idle, ~5 MB RSS. `debug.vib.log` set back to 0. | - |
| 2026-11-12 | PC: `apply.sh status` now detects the HAL by process (init.svc.* isn't readable from adb shell). | - |
| 2026-11-14 | Phone (read-only): pulled the JamesDSP preset `Oneplus_8_speakers.tar` (your final speaker curve, saved 2026-11-02) to `files/jamesdsp/`; checksum identical to the phone's copy. Noted that QS tile haptics are now ON (`system qs_tile_haptic=1`), which you changed yourself after 2026-11-12. Nothing was written to the phone. | - |
| 2026-11-14 | PC: `JAMESDSP.md` records every value in the preset. `apply.sh postboot` copies the preset to `Download/` if JamesDSP doesn't have it yet, and prints the taps for speaker-only use (Per-device profiles). It never overwrites a different file. `apply.sh status` shows whether the app holds this exact preset. The overlay rc moved from a heredoc in `apply.sh` to `files/odm_overlay.rc` (byte-identical to the installed one); `files/SHA256SUMS` updated. | restore `apply.sh` from before this change, or delete `jdsp_preset` |
| 2026-11-14 | PC: `flashable/`: `update-binary` (the installer), `build.sh`, `test.sh` (fake-recovery tests, 60/60 pass under dash and busybox sh), `README.md`. Built `out/oneplus8-fixes-20261114.zip` (installs the overlay fixes, same result as `apply.sh recovery`) and `out/oneplus8-fixes-uninstall-20261114.zip`. Not flashed or run on the phone yet. | delete `flashable/` |
| 2026-11-14 | Repo (github.com/the-platapus/oneplus8-crdroid-qol): README with the EQ chart (`docs/eq-curve.svg`, drawn from the preset by `docs/eq-curve.py`); `.gitignore` for `haptics-hal/out/` and `flashable/out/` (both untracked; they were in the first commit); `.gitattributes` keeps `files/` byte-exact; CI workflow `.github/workflows/flashable.yml` builds and tests the zips on every push and publishes a Release for `v*` tags; `build.sh` takes VER from the tag and builds byte-identical zips; `test.sh` also runs under mksh (90/90 pass). | revert the commit |
| 2026-11-14 | PC: `apply.sh` now covers the rest of the haptics setup. `postboot` turns on brightness and volume slider haptics, but only when our HAL is running (on the ROM's HAL they buzz); QS tile haptics are left as they are. `status` shows all three toggles. `recovery` and `remove` keep the recovery screen at 2% until reboot (`RECOVERY_BRIGHTNESS=<percent>`, 0 = leave it). `remove` now warns that the sliders buzz again on the ROM's HAL. Tested against a fake adb (phone not connected); not yet run on the phone. | delete `dim_recovery` and the Haptics block in `cmd_postboot` |

## Current state (end of 2026-11-12)

- Build 3 of `haptics-hal` is installed and active (`./apply.sh status` -> "Vibrator HAL: OnePlus 8 HAL (running)").
- Defaults: CLICK wf1 @2500 gain 48..128; TICK wf1 @1400 gain 24..100; LOW_TICK wf2 @1400 gain 20..42 linear
  (reported 4 ms); THUD wf4 @2500 gain 48..128; amplitude max gain 117; coalesce on; tail stop off for
  primitives; prebaked effects identical to stock but reported as 20 ms.
- crDroid toggles: brightness slider haptics ON, volume slider haptics ON (you turned them on), QS tile haptics ON
  (you turned it on after 2026-11-12; `postboot` leaves this one alone).
- After a ROM update: boot to recovery, Mount system + Enable ADB, `./apply.sh recovery` (it skips the HAL by
  itself if the ROM's vibrator stack changed). The reboot then runs `postboot`, which turns the brightness and
  volume slider haptics back on if a clean flash reset them. Or, without python/bash on the PC, sideload
  `flashable/out/oneplus8-fixes-<date>.zip` in recovery (`flashable/README.md`); after a clean flash still run
  `./apply.sh postboot` for the app-side steps. Rebuild from source: `haptics-hal/build.sh`, then copy
  `haptics-hal/out/android.hardware.vibrator-service.op8` to `files/` and refresh `files/SHA256SUMS`.

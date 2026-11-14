# JamesDSP speaker curve (OnePlus 8)

Your final tuning for the phone's own speakers, matched by ear against an iPhone 13.

- File: `files/jamesdsp/Oneplus_8_speakers.tar`, a JamesDSP preset
- sha256: `c55ab3901c62e9b2245b77125c19840230e3a13290430957348761e9bc3519cd`
- Saved by JamesDSP 1.6.14 (root build, `app_flavor=rootFull`, preset format version 3) on 2026-11-02 07:24
- Backed up 2026-11-14 by copying it off the phone (read-only) from
  `/sdcard/Android/data/james.dsp/files/Presets/Oneplus_8_speakers.tar`. It is byte-identical to the phone's copy.

## What it does

Two things are active.

**Graphic EQ: on.** The 19 points:

| Hz | 55 | 77 | 110 | 156 | 220 | 311 | 440 | 622 | 880 | 1200 | 1800 | 2500 | 3500 | 5000 | 6000 | 7000 | 10000 | 14000 | 20000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dB | 0 | 0 | 0 | 0 | 0 | -6 | -7.5 | -6 | -5 | -4.5 | -2.5 | -2 | -5 | -3.5 | +2 | -2 | 0 | 0 | 0 |

The exact stored string (`geq_nodes`), including the trailing space:

```
GraphicEQ: 55 0; 77 0; 110 0; 156 0; 220 0; 311 -6; 440 -7.5; 622 -6; 880 -5; 1200 -4.5; 1800 -2.5; 2500 -2; 3500 -5; 5000 -3.5; 6000 2; 7000 -2; 10000 0; 14000 0; 20000 0; 
```

**Output control:** post gain `-0.2924618` dB, limiter threshold `-0.1` dB, limiter release `60.0` ms.

## Everything else is off

The preset stores these values, but none of them is applied:

| Effect | Switch | Stored settings |
|---|---|---|
| Multimodal equalizer | `eq_enable=false` | filter type 0, interpolation 0, bands 25 to 16000 Hz all 0.0 dB |
| Bass boost | `bass_enable=false` | max gain 5.0 |
| Compander | not stored (app default: off) | time constant 0.22, transforms 0 |
| Reverb | `reverb_enable=false` | preset 15 |
| Crossfeed (BS2B) | `bs2b_crossfeed_enable=false` | mode 5 |
| Stereo widener | `stereowide_enable=false` | mode 61.64669 |
| Tube | `tube_enable=false` | drive 12.0 |
| ViPER-DDC | `ddc_enable=false` | no file |
| Convolver | `convolver_enable=false` | mode 0, no file, adv `-80;-100;0;0;0;0` |
| Liveprog | `liveprog_enable=false` | `Liveprog/depthsurround.eel`, a copy of which is inside the preset |

Three keys aren't stored in the preset, so loading it gives them the app's defaults: `compander_enable` (off),
`compander_granularity` (0) and `compander_response` (the app's default curve). The compander is off, so this
changes nothing you hear.

Per-file save times inside the preset: graphic EQ 2026-11-02 07:04:25, output control 2026-11-01 23:01:55,
stereo widener 07:24:17. The other effects were saved between 2026-10-30 and 2026-11-02.

## Using it on the phone speaker only

JamesDSP's **Per-device profiles** gives every output (phone speaker, wired headphones, each Bluetooth device)
its own settings and switches automatically. With it on, loading a preset changes only the active profile.

1. Open JamesDSP.
2. Settings > Device profiles > turn on **Per-device profiles**.
3. Unplug headphones and disconnect Bluetooth audio, so **Active device profile** on the main screen is the
   phone speaker.
4. Presets > **Import** > pick `Oneplus_8_speakers.tar`, then tap it to load it.

New devices start with a blank profile.

## Where this is applied

- **After a ROM update** (dirty flash): nothing to do. JamesDSP's settings and profiles live in /data and survive.
- **After a clean flash:** `./apply.sh postboot` installs JamesDSP, copies the preset to `Download/` and prints
  the four steps above. Without root, adb can't change another app's settings, so the taps are yours.
  `./apply.sh status` shows whether the app's Presets folder holds this exact preset.
- **Flashable zip:** carries a copy in `jamesdsp/` inside the zip, so the curve travels with it. The zip can't
  apply it, because in recovery the app's storage is encrypted and JamesDSP isn't running.

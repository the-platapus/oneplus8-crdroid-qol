#!/usr/bin/env bash
# Prints the GitHub Release notes for flashable/out/*-<ver>.zip (used by CI, works locally too).
#   ./release-notes.sh 20261114
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VER=${1:?usage: release-notes.sh <ver>}
SUMS="$HERE/out/SHA256SUMS-$VER"
[ -f "$SUMS" ] || { echo "no $SUMS; run VER=$VER ./build.sh first" >&2; exit 1; }
REPO=${GITHUB_REPOSITORY:-the-platapus/oneplus8-crdroid-qol}
REF=${GITHUB_SHA:-$(git -C "$HERE" rev-parse HEAD)}

cat <<EOF
Flashable fixes for the **OnePlus 8** (\`instantnoodle\`) on **crDroid 16**.

| File | Does |
|---|---|
| \`oneplus8-fixes-$VER.zip\` | Installs the Dolby library, the JamesDSP effect + \`audio_effects.xml\` entry, the thermal trip points and the haptics HAL. Each part is skipped if the ROM no longer needs it. |
| \`oneplus8-fixes-uninstall-$VER.zip\` | Removes all of them. |

### Flashing

1. Boot to recovery and tap **Apply update › Apply from ADB**.
2. Run \`adb sideload oneplus8-fixes-$VER.zip\`. Recovery says the signature can't be verified: tap **Yes**.
3. Reboot.

After a **clean** flash, run \`./apply.sh postboot\` from the repo for the JamesDSP app, its speaker preset and the slider haptics. A ROM update keeps those.

Everything is checked and test-mounted in recovery's RAM before \`/system\` is touched. A no-write dry run is in [flashable/README.md](https://github.com/$REPO/blob/$REF/flashable/README.md#dry-run-writes-nothing-to-the-phones-storage).

### SHA-256

\`\`\`
$(cat "$SUMS")
\`\`\`

CI tests these zips against a fake recovery under mksh, dash and busybox sh. They aren't flashed on a phone by CI.
EOF

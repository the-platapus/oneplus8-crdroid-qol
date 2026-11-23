#!/usr/bin/env bash
# Builds libbluetooth_jni.so.patched from the crDroid 16 original (com.android.bt 361099999).
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
A="$D/apex"
RE=$(cat "$A/tools.path")
ORIG="$A/libbluetooth_jni.so"
OUT="$D/libbluetooth_jni.so.patched"

echo "original sha256: $(sha256sum "$ORIG" | cut -d' ' -f1)"

CAVE=0xdf1e80
SYMS=(--defsym=osi_property_get_bool=0xd97370 --defsym=rmutex_lock=0x2e9408
      --defsym=rmutex_unlock=0x2e9434 --defsym=dispatch_sm_event=0x60f560
      --defsym=btif_av_source=0xe65248 --defsym=orig_continue=0x61beb4)

cd "$D"
"$RE/clang" --target=aarch64-linux-android35 -c cave.S -o cave.o
"$RE/ld.lld" -static --no-pie -e dual_start -Ttext=$CAVE "${SYMS[@]}" cave.o -o cave.elf
"$RE/llvm-objcopy" -O binary --only-section=.text cave.elf cave.bin

printf '\t.text\n\tb dual_start\n' > entry.S
"$RE/clang" --target=aarch64-linux-android35 -c entry.S -o entry.o
"$RE/ld.lld" -static --no-pie -e 0 -Ttext=0x61beb0 --defsym=dual_start=$CAVE entry.o -o entry.elf
"$RE/llvm-objcopy" -O binary --only-section=.text entry.elf entry.bin

python3 -I - "$ORIG" "$OUT" cave.bin entry.bin <<'EOF'
import struct, sys
orig, out, cave_f, entry_f = sys.argv[1:]
so = bytearray(open(orig, 'rb').read())
cave = open(cave_f, 'rb').read(); entry = open(entry_f, 'rb').read()
CAVE, CAVE_END = 0xdf1e80, 0xdf2000
def word(off): return struct.unpack_from('<I', so, off)[0]
# Patch sites must hold exactly what we disassembled (file offset == vaddr in this segment).
assert word(0x61beb0) == 0xf800865e, hex(word(0x61beb0))      # str x30, [x18], #8
assert word(0x616acc) & 0xff00001f == 0x36000000, hex(word(0x616acc))  # tbz w0, #0, ...
assert len(cave) <= CAVE_END - CAVE, len(cave)
assert not any(so[0xdf1e30:CAVE_END]), 'padding not zero'
# ELF program header 2 = the R+E LOAD segment ending at 0xdf1e30.
e_phoff = struct.unpack_from('<Q', so, 0x20)[0]; e_phentsize, e_phnum = struct.unpack_from('<HH', so, 0x36)
ph = e_phoff + 2 * e_phentsize
p_type, p_flags, p_off, p_va, p_pa, p_filesz, p_memsz, p_align = struct.unpack_from('<IIQQQQQQ', so, ph)
assert (p_type, p_flags, p_off, p_va, p_filesz, p_memsz) == (1, 5, 0x2db000, 0x2db000, 0xb16e30, 0xb16e30), \
    (p_type, p_flags, hex(p_off), hex(p_va), hex(p_filesz), hex(p_memsz))
new_size = CAVE_END - p_va
struct.pack_into('<QQ', so, ph + 0x20, new_size, new_size)
so[CAVE:CAVE + len(cave)] = cave
so[0x61beb0:0x61beb4] = entry
struct.pack_into('<I', so, 0x616acc, 0xd503201f)                   # nop
open(out, 'wb').write(so)
print(f'cave {len(cave)} bytes at 0x{CAVE:x}; segment 2 size 0x{p_filesz:x} -> 0x{new_size:x}')
EOF
sha256sum "$OUT"

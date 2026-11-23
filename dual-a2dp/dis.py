#!/usr/bin/env python3
# Disassemble one function of libbluetooth_jni.so, labelling branch/call targets with symbol names.
import bisect, re, subprocess, sys
W = sys.argv[1]; name = sys.argv[2]
RE = open(f'{W}/tools.path').read().strip()
syms = []
for l in open(f'{W}/syms.txt'):
    p = l.rstrip('\n').split(' ', 2)
    if len(p) == 3 and p[1] in 'tTwW': syms.append((int(p[0], 16), p[2]))
syms.sort(); addrs = [a for a, _ in syms]
def sym(a):
    i = bisect.bisect_right(addrs, a) - 1
    return f'{syms[i][1]}+0x{a - syms[i][0]:x}' if i >= 0 else '?'
cands = [(a, n) for a, n in syms if n == name or n.startswith(name + '(')]
if not cands: sys.exit(f'no symbol {name}')
start, full = cands[0]
end = addrs[addrs.index(start) + 1]
print(f'== {full} @0x{start:x}..0x{end:x} ({end - start} bytes)')
out = subprocess.run([f'{RE}/llvm-objdump', '-d', '--no-show-raw-insn', f'--start-address=0x{start:x}', f'--stop-address=0x{end:x}', f'{W}/libbluetooth_jni.so'], capture_output=True, text=True).stdout
for l in out.splitlines():
    m = re.match(r'\s*([0-9a-f]+):\s+(.*)', l)
    if not m: continue
    ins = m.group(2)
    t = re.search(r'\b(?:bl?|b\.\w+|cbn?z|tbn?z|adrp)\b.*?0x([0-9a-f]+)', ins)
    note = ''
    if t and not ins.startswith('adrp'): note = '   ; ' + sym(int(t.group(1), 16))
    print(f'{m.group(1)}: {ins}{note}')

#!/usr/bin/env python3
"""Extract one partition image from an Android A/B OTA (zip with payload.bin).

Standard library only: a minimal protobuf reader for DeltaArchiveManifest and the full-OTA
operation types (REPLACE, REPLACE_BZ, REPLACE_XZ, ZSTD, ZERO, DISCARD). Each operation's data is
checked against its SHA-256 from the manifest.
  payload_extract.py <ota.zip> <partition> <out.img>
"""
import bz2, hashlib, lzma, struct, sys, zipfile

def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1; r |= (c & 0x7f) << s; s += 7
        if c < 0x80: return r, i

def fields(b):
    i = 0
    while i < len(b):
        key, i = varint(b, i); fn, wt = key >> 3, key & 7
        if wt == 0: v, i = varint(b, i)
        elif wt == 2:
            n, i = varint(b, i); v = b[i:i + n]; i += n
        elif wt == 1: v = b[i:i + 8]; i += 8
        elif wt == 5: v = b[i:i + 4]; i += 4
        else: raise ValueError(f'wire type {wt}')
        yield fn, v

def main(ota, part, out):
    z = zipfile.ZipFile(ota)
    info = z.getinfo('payload.bin')
    assert info.compress_type == zipfile.ZIP_STORED, 'payload.bin must be stored'
    f = z.open(info)
    magic, ver, man_len = struct.unpack('>4sQQ', f.read(20))
    assert magic == b'CrAU' and ver == 2, (magic, ver)
    sig_len, = struct.unpack('>I', f.read(4))
    manifest = f.read(man_len); f.read(sig_len)
    data_start = 24 + man_len + sig_len
    block_size = 4096
    pu = None
    for fn, v in fields(manifest):
        if fn == 3: block_size = v
        if fn == 13:
            name = next((x for n, x in fields(v) if n == 1), b'').decode()
            if name == part: pu = v
    if pu is None: sys.exit(f'no partition {part}')
    ops = [v for n, v in fields(pu) if n == 8]
    size = next((dict(fields(v)).get(1) for n, v in fields(pu) if n == 7), None)
    print(f'{part}: {len(ops)} operations, {size} bytes, block {block_size}')
    zstd = None
    with open(out, 'wb') as o:
        if size: o.truncate(size)
        for k, op in enumerate(ops):
            d = {}; dst = []
            for n, v in fields(op):
                if n == 6: dst.append(dict(fields(v)))
                else: d[n] = v
            typ, off, ln = d.get(1, 0), d.get(2, 0), d.get(3, 0)
            blob = b''
            if ln:
                f.seek(data_start + off); blob = f.read(ln)
                if 8 in d: assert hashlib.sha256(blob).digest() == d[8], f'op {k}: data hash mismatch'
            if typ == 0: raw = blob
            elif typ == 1: raw = bz2.decompress(blob)
            elif typ == 8: raw = lzma.decompress(blob)
            elif typ == 14:
                if zstd is None:
                    from compression import zstd   # Python 3.14+
                raw = zstd.decompress(blob)
            elif typ in (6, 7): raw = None
            else: sys.exit(f'op {k}: type {typ} is a delta operation; need a full OTA')
            pos = 0
            for e in dst:
                start, nb = e.get(1, 0), e.get(2, 0)
                o.seek(start * block_size)
                n = nb * block_size
                if raw is None: o.write(b'\0' * n)
                else: o.write(raw[pos:pos + n]); pos += n
    print(f'wrote {out}')

if __name__ == '__main__':
    main(*sys.argv[1:4])

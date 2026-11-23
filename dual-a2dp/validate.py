#!/usr/bin/env python3
"""Check a repacked com.android.bt.capex the way apexd and PackageManager will, plus stricter checks.

  validate.py <crDroid original.capex> <repacked.capex> [<expected libbluetooth_jni.so>]

apexd (ValidateDecompressedApex, VerifyApexVerity): capex apex_pubkey == original_apex apex_pubkey; same
version; capexMetadata.originalApexDigest == the payload's verified root digest; vbmeta signed by the bundled
key; hashtree valid. PackageManager: a valid v3 signature on both zips. Also: the payload is stored and
4096-aligned; every other entry is byte-identical to crDroid's; the ext4 payload passes e2fsck; and
apart from the library, every byte of the filesystem is identical to crDroid's.
"""
import hashlib, io, os, re, struct, subprocess, sys, tempfile, zipfile

W = os.path.dirname(os.path.abspath(__file__))
AVBTOOL = [sys.executable, '-I', os.path.join(W, 'src', 'avbtool.py')]
BT = open(os.path.join(W, 'apex', 'buildtools.path')).read().strip()
LIB = '/lib64/libbluetooth_jni.so'
ok = fail = 0

def check(cond, what):
    global ok, fail
    if cond: ok += 1; print(f'  ok    {what}')
    else: fail += 1; print(f'  FAIL  {what}')

def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def pb_fields(b):
    i, out = 0, []
    while i < len(b):
        k = 0; s = 0
        while True:
            c = b[i]; i += 1; k |= (c & 0x7f) << s; s += 7
            if c < 0x80: break
        fn, wt = k >> 3, k & 7
        if wt == 0:
            v = 0; s = 0
            while True:
                c = b[i]; i += 1; v |= (c & 0x7f) << s; s += 7
                if c < 0x80: break
        else:
            n = 0; s = 0
            while True:
                c = b[i]; i += 1; n |= (c & 0x7f) << s; s += 7
                if c < 0x80: break
            v = b[i:i + n]; i += n
        out.append((fn, v))
    return out

def data_offset(zbytes, info):
    n, m = struct.unpack('<HH', zbytes[info.header_offset + 26:info.header_offset + 30])
    return info.header_offset + 30 + n + m

def main(orig_path, new_path, lib=None):
    tmp = tempfile.mkdtemp()
    oc, nc = zipfile.ZipFile(orig_path), zipfile.ZipFile(new_path)
    nc_bytes = open(new_path, 'rb').read()
    print('== containers')
    for label, path in (('capex', new_path),):
        r = run(f'{BT}/apksigner', 'verify', '-v', path)
        check(r.returncode == 0 and 'v3 scheme (APK Signature Scheme v3): true' in r.stdout, f'{label}: valid v3 signature')
    nab = nc.read('original_apex'); oab = oc.read('original_apex')
    open(f'{tmp}/original_apex', 'wb').write(nab)
    r = run(f'{BT}/apksigner', 'verify', '-v', f'{tmp}/original_apex')
    check(r.returncode == 0 and 'v3 scheme (APK Signature Scheme v3): true' in r.stdout, 'original_apex: valid v3 signature')
    na, oa = zipfile.ZipFile(io.BytesIO(nab)), zipfile.ZipFile(io.BytesIO(oab))
    check([i.filename for i in nc.infolist() if not i.filename.startswith('META-INF')] ==
          [i.filename for i in oc.infolist() if not i.filename.startswith('META-INF')], 'capex: same entries, same order')
    check([i.filename for i in na.infolist() if not i.filename.startswith('META-INF')] ==
          [i.filename for i in oa.infolist() if not i.filename.startswith('META-INF')], 'original_apex: same entries, same order')
    pi = na.getinfo('apex_payload.img')
    check(pi.compress_type == zipfile.ZIP_STORED and data_offset(nab, pi) % 4096 == 0, 'payload stored and 4096-aligned')
    for n in ('AndroidManifest.xml', 'apex_build_info.pb', 'apex_manifest.pb', 'assets/NOTICE.html.gz', 'resources.arsc'):
        check(na.read(n) == oa.read(n), f'original_apex/{n} identical to crDroid\'s')
    for n in ('AndroidManifest.xml', 'apex_build_info.pb'):
        check(nc.read(n) == oc.read(n), f'capex/{n} identical to crDroid\'s')

    print('== apexd checks')
    cpub, apub = nc.read('apex_pubkey'), na.read('apex_pubkey')
    check(cpub == apub, 'capex apex_pubkey == original_apex apex_pubkey')
    r = run(*AVBTOOL, 'extract_public_key', '--key', f'{W}/keys/apex_payload.pem', '--output', f'{tmp}/pub')
    check(open(f'{tmp}/pub', 'rb').read() == apub, 'bundled key is our key')
    check(apub != oa.read('apex_pubkey'), 'key differs from crDroid\'s (so apexd re-decompresses)')
    cman, aman = dict(pb_fields(nc.read('apex_manifest.pb'))), dict(pb_fields(na.read('apex_manifest.pb')))
    check(cman[1] == aman[1] == b'com.android.bt' and cman[2] == aman[2] == 361099999, 'same name and version 361099999')
    digest = dict(pb_fields(cman[12]))[1].decode()
    open(f'{tmp}/payload.img', 'wb').write(na.read('apex_payload.img'))
    r = run(*AVBTOOL, 'verify_image', '--image', f'{tmp}/payload.img', '--key', f'{W}/keys/apex_payload.pem')
    check(r.returncode == 0, 'vbmeta signature and hashtree verify with the bundled key')
    info = run(*AVBTOOL, 'info_image', '--image', f'{tmp}/payload.img').stdout
    root = re.search(r'Root Digest:\s+(\S+)', info).group(1)
    check(root == digest, f'capexMetadata digest == payload root digest ({root[:16]}…)')

    print('== filesystem')
    size = int(re.search(r'Original image size:\s+(\d+)', info).group(1))
    new_fs = open(f'{tmp}/payload.img', 'rb').read()[:size]
    old_fs = oa.read('apex_payload.img')[:size]
    open(f'{tmp}/fs.img', 'wb').write(new_fs)
    r = run('e2fsck', '-fn', f'{tmp}/fs.img')
    check(r.returncode == 0, 'e2fsck -fn: clean')
    diff_blocks = [b for b in range(size // 4096) if new_fs[b * 4096:(b + 1) * 4096] != old_fs[b * 4096:(b + 1) * 4096]]
    if lib is None:
        check(not diff_blocks, 'filesystem byte-identical to crDroid\'s')
    else:
        blocks = set(int(b) for b in run('debugfs', '-R', f'blocks {LIB}', f'{tmp}/fs.img').stdout.split())
        check(diff_blocks and set(diff_blocks) <= blocks, f'{len(diff_blocks)} changed blocks, all inside {LIB}')
        r = run('debugfs', '-R', f'dump {LIB} {tmp}/lib', f'{tmp}/fs.img')
        check(open(f'{tmp}/lib', 'rb').read() == open(lib, 'rb').read(), f'{LIB} in the image == {os.path.basename(lib)}')
        st_new = run('debugfs', '-R', f'stat {LIB}', f'{tmp}/fs.img').stdout
        open(f'{tmp}/ofs.img', 'wb').write(old_fs)
        st_old = run('debugfs', '-R', f'stat {LIB}', f'{tmp}/ofs.img').stdout
        strip = lambda s: re.sub(r'(?m)^.*(time|Inode checksum|crtime).*$', '', s)
        check(strip(st_new) == strip(st_old), 'library inode (size, mode, owner, xattrs/label) unchanged')
    print(f'{ok} ok, {fail} failed')
    return fail == 0

if __name__ == '__main__':
    sys.exit(0 if main(*sys.argv[1:4]) else 1)

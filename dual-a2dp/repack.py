#!/usr/bin/env python3
"""Repack crDroid 16's com.android.bt.capex with our own keys, optionally swapping libbluetooth_jni.so.

  repack.py <orig.capex> <libbluetooth_jni.so | -> <outdir>

The library is rewritten in place on its own data blocks inside the ext4 payload, so the file's size,
inode, owner and SELinux label are untouched. Layout follows the original exactly:
  original_apex: apex_payload.img (stored, 4096-aligned), assets/NOTICE.html.gz, resources.arsc (stored),
                 AndroidManifest.xml, apex_build_info.pb, apex_manifest.pb, apex_pubkey (deflated),
                 v1 + v3 signature.
  capex:         AndroidManifest.xml, apex_build_info.pb, apex_manifest.pb (+ capexMetadata root digest),
                 apex_pubkey (stored), original_apex (deflated), v1 + v3 signature.
Payload: AVB hashtree footer, SHA256_RSA4096, sha256, 4096-byte blocks, no FEC, the ORIGINAL salt,
prop apex.key=com.android.bt. With "-" (unchanged library) the root digest must equal crDroid's.
"""
import hashlib, os, re, shutil, subprocess, sys, zipfile

W = os.path.dirname(os.path.abspath(__file__))
AVBTOOL = [sys.executable, '-I', os.path.join(W, 'src', 'avbtool.py')]
BT = open(os.path.join(W, 'apex', 'buildtools.path')).read().strip()
KEYS = os.path.join(W, 'keys')
SALT = '2a90c2edd99dc7a8c285ef2906eea235a5ec53d0f73d01c8010649ea6c240ed7'
ORIG_DIGEST = 'f35548b46904ffee31759b221faed5ba60e8e484c2f4e764218f67fd6f74b8ed'
LIB = '/lib64/libbluetooth_jni.so'
DATE = (2009, 1, 1, 0, 0, 0)

def run(*cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode: sys.exit(f'FAILED: {" ".join(cmd)}\n{r.stdout}{r.stderr}')
    return r.stdout

def sha(b): return hashlib.sha256(b).hexdigest()

def avb_info(img):
    out = run(*AVBTOOL, 'info_image', '--image', img)
    return {k: re.search(rf'{k}:\s+(\S+)', out).group(1) for k in ('Root Digest', 'Image size', 'Salt', 'Original image size')}

def write_zip(path, entries):
    """entries: list of (name, bytes, compress_type)"""
    with zipfile.ZipFile(path, 'w') as z:
        for name, data, ct in entries:
            zi = zipfile.ZipInfo(name, DATE); zi.compress_type = ct; zi.external_attr = 0o644 << 16
            z.writestr(zi, data)

def sign(unsigned, out, align):
    tmp = out + '.aligned'
    if align: run(f'{BT}/zipalign', '-f', '4096', unsigned, tmp)
    else: shutil.copy(unsigned, tmp)
    run(f'{BT}/apksigner', 'sign', '--alignment-preserved', 'true',
        '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'false', '--v3-signing-enabled', 'true',
        '--key', f'{KEYS}/container.pk8', '--cert', f'{KEYS}/container.x509.pem', '--out', out, tmp)
    os.remove(tmp); os.remove(unsigned)
    for f in (out + '.idsig',):
        if os.path.exists(f): os.remove(f)

def manifest_with_digest(inner, digest):
    d = digest.encode(); assert len(d) == 64
    sub = b'\x0a' + bytes([len(d)]) + d                      # CapexMetadata.originalApexDigest (1)
    return inner + b'\x62' + bytes([len(sub)]) + sub          # ApexManifest.capexMetadata (12)

def main(capex_path, lib_path, outdir):
    os.makedirs(outdir, exist_ok=True)
    capex = zipfile.ZipFile(capex_path)
    apex = zipfile.ZipFile(capex.open('original_apex'))
    names = [i.filename for i in apex.infolist() if not i.filename.startswith('META-INF/')]
    ctypes = {i.filename: i.compress_type for i in apex.infolist()}

    # 1. payload: strip the footer, optionally swap the library on its own blocks, re-footer with our key.
    img = os.path.join(outdir, 'apex_payload.img')
    open(img, 'wb').write(apex.read('apex_payload.img'))
    orig_info = avb_info(img)
    assert orig_info['Salt'] == SALT and orig_info['Root Digest'] == ORIG_DIGEST, orig_info
    run(*AVBTOOL, 'erase_footer', '--image', img)
    assert os.path.getsize(img) == int(orig_info['Original image size'])
    if lib_path != '-':
        new = open(lib_path, 'rb').read()
        stat = run('debugfs', '-R', f'stat {LIB}', img)
        size = int(re.search(r'Size: (\d+)', stat).group(1))
        assert size == len(new), f'library size differs: {size} vs {len(new)}'
        blocks = [int(b) for b in run('debugfs', '-R', f'blocks {LIB}', img).split()]
        assert len(blocks) == (size + 4095) // 4096, (len(blocks), size)
        with open(img, 'r+b') as f:
            for i, b in enumerate(blocks):
                f.seek(b * 4096); f.write(new[i * 4096:(i + 1) * 4096])
        back = os.path.join(outdir, 'lib.check')
        run('debugfs', '-R', f'dump {LIB} {back}', img)
        assert open(back, 'rb').read() == new, 'library read back from the image differs'
        os.remove(back)
    run(*AVBTOOL, 'add_hashtree_footer', '--image', img,
        '--do_not_generate_fec', '--hash_algorithm', 'sha256', '--salt', SALT,
        '--algorithm', 'SHA256_RSA4096', '--key', f'{KEYS}/apex_payload.pem',
        '--prop', 'apex.key:com.android.bt')
    info = avb_info(img)
    assert info['Image size'] == orig_info['Image size'], (info, orig_info)
    if lib_path == '-':
        assert info['Root Digest'] == ORIG_DIGEST, f'unchanged payload gave a different root digest {info}'
    pubkey = os.path.join(outdir, 'apex_pubkey')
    run(*AVBTOOL, 'extract_public_key', '--key', f'{KEYS}/apex_payload.pem', '--output', pubkey)
    pub = open(pubkey, 'rb').read()

    # 2. original_apex
    data = {n: apex.read(n) for n in names}
    data['apex_payload.img'] = open(img, 'rb').read(); data['apex_pubkey'] = pub
    apex_out = os.path.join(outdir, 'original_apex')
    write_zip(apex_out + '.unsigned', [(n, data[n], ctypes[n]) for n in names])
    sign(apex_out + '.unsigned', apex_out, align=True)

    # 3. capex
    inner = data['apex_manifest.pb']
    man = manifest_with_digest(inner, info['Root Digest'])
    if lib_path == '-':
        assert man == capex.read('apex_manifest.pb'), 'rebuilt capex manifest differs from crDroid\'s'
    cdata = {'AndroidManifest.xml': capex.read('AndroidManifest.xml'), 'apex_build_info.pb': capex.read('apex_build_info.pb'),
             'apex_manifest.pb': man, 'apex_pubkey': pub, 'original_apex': open(apex_out, 'rb').read()}
    cnames = [i.filename for i in capex.infolist() if not i.filename.startswith('META-INF/')]
    cct = {i.filename: i.compress_type for i in capex.infolist()}
    out = os.path.join(outdir, 'com.android.bt.capex')
    write_zip(out + '.unsigned', [(n, cdata[n], cct[n]) for n in cnames])
    sign(out + '.unsigned', out, align=False)
    print(f'root digest {info["Root Digest"]}  payload {info["Image size"]} bytes')
    print(f'{out}  sha256 {sha(open(out, "rb").read())}')

if __name__ == '__main__':
    main(*sys.argv[1:4])

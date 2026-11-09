#!/usr/bin/env python3
"""M3.7: list sha256 sums of the regular files in a gzip cpio (newc) ramdisk.

  gen_manifest.py BOOT_IMG OUT_RAMDISK_GZ OUT_MANIFEST

Parses the archive directly, so nothing is extracted or executed. The
manifest is in `sha256sum -c` format, with paths relative to / .
"""
import gzip
import hashlib
import stat
import struct
import sys

boot, out_rd, out_man = sys.argv[1:4]
d = open(boot, "rb").read()
ks, _, rs, *_rest = struct.unpack("<8I", d[8:40])
ps = _rest[4]
off = ps * ((ks + ps - 1) // ps + 1)
rd = d[off:off + rs]
open(out_rd, "wb").write(rd)
a = gzip.decompress(rd)

pos, lines, others = 0, [], 0
while True:
    if a[pos:pos + 6] != b"070701":
        sys.exit(f"bad cpio magic at {pos}")
    f = [int(a[pos + 6 + 8 * i:pos + 14 + 8 * i], 16) for i in range(13)]
    mode, fsize, nsize = f[1], f[6], f[11]
    name = a[pos + 110:pos + 110 + nsize - 1].decode()
    data = (pos + 110 + nsize + 3) & ~3
    if name == "TRAILER!!!":
        break
    if stat.S_ISREG(mode) and fsize:
        lines.append(f"{hashlib.sha256(a[data:data + fsize]).hexdigest()}  ./{name}")
    else:
        others += 1
    pos = (data + fsize + 3) & ~3
open(out_man, "w").write("\n".join(lines) + "\n")
print(f"ramdisk {rs} B, {len(lines)} regular files, {others} other entries")

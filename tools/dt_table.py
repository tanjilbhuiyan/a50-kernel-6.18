#!/usr/bin/env python3
"""Parse, round-trip and rebuild Android dt_table images (magic d7b7ab1e).

Used for the A50 DTB/DTBO partitions (M2.3). Stdlib only; run as
`python3 -I tools/dt_table.py ...`.

Layout of a stock A50 image (verified on reference/stock-images/*.img):

    [dt_table header 32 B][entry 32 B * n][FDT blobs, contiguous]   <- "table"
    [Samsung signature block, 528 B, starts with b"SignerVer02"]    \
    [zeros]                                                          } "tail",
    [AVB0 vbmeta blob @ 4 KiB boundary][zeros][AVBf footer, 64 B]    / opaque
    ... padded with zeros to the 8 MiB partition size.

The tail is kept byte-for-byte; only the table is regenerated.

  info IMG                       print header, entries, tail layout
  extract IMG OUTDIR             write entry blobs + tail + manifest.json
  roundtrip IMG                  parse, rebuild, require identical bytes
  build IMG OUT --set IDX=FDT... replace entries of IMG, keep all table
                                 fields; replaced blobs are zero-padded to the
                                 stock dt_size unless --no-pad is given
"""
import argparse
import json
import os
import struct
import sys

MAGIC = 0xD7B7AB1E
HDR = struct.Struct(">8I")    # magic total_size header_size entry_size count entries_off page_size version
ENT = struct.Struct(">8I")    # dt_size dt_offset id rev custom[4]


class DtTable:
    def __init__(self, header, entries, tail, image_size):
        self.header = header          # dict of the 8 header fields
        self.entries = entries        # list of dict(id, rev, custom, blob)
        self.tail = tail              # bytes after total_size, up to image_size
        self.image_size = image_size
        self.tail_at = header["total_size"]

    @classmethod
    def parse(cls, data):
        names = ("magic", "total_size", "header_size", "dt_entry_size",
                 "dt_entry_count", "dt_entries_offset", "page_size", "version")
        h = dict(zip(names, HDR.unpack_from(data, 0)))
        if h["magic"] != MAGIC:
            raise ValueError("bad magic %#x" % h["magic"])
        if h["header_size"] != HDR.size or h["dt_entry_size"] != ENT.size:
            raise ValueError("unexpected header/entry size")
        entries, expect = [], h["dt_entries_offset"] + h["dt_entry_count"] * ENT.size
        for i in range(h["dt_entry_count"]):
            f = ENT.unpack_from(data, h["dt_entries_offset"] + i * ENT.size)
            size, off = f[0], f[1]
            if off != expect:
                raise ValueError("entry %d not contiguous (off %d, expected %d)" % (i, off, expect))
            expect += size
            blob = data[off:off + size]
            if blob[:4] != b"\xd0\x0d\xfe\xed":
                raise ValueError("entry %d is not an FDT" % i)
            entries.append({"id": f[2], "rev": f[3], "custom": list(f[4:8]), "blob": blob})
        if expect != h["total_size"]:
            raise ValueError("total_size %d != end of blobs %d" % (h["total_size"], expect))
        return cls(h, entries, data[h["total_size"]:], len(data))

    def build(self):
        h = self.header
        off = h["dt_entries_offset"] + len(self.entries) * ENT.size
        ents, blobs = [], []
        for e in self.entries:
            ents.append(ENT.pack(len(e["blob"]), off, e["id"], e["rev"], *e["custom"]))
            blobs.append(e["blob"])
            off += len(e["blob"])
        hdr = HDR.pack(MAGIC, off, h["header_size"], h["dt_entry_size"], len(self.entries),
                       h["dt_entries_offset"], h["page_size"], h["version"])
        table = hdr + b"".join(ents) + b"".join(blobs)
        if len(table) > self.tail_at:
            raise ValueError("table (%d B) overruns the tail at %d; use stock-sized blobs"
                             % (len(table), self.tail_at))
        out = table + b"\0" * (self.tail_at - len(table)) + self.tail
        assert len(out) == self.image_size
        return out

    def avb(self):
        """Describe the opaque tail (informational)."""
        t, info = self.tail, {}
        if t[-64:-60] == b"AVBf":
            info["avb_footer"] = {
                "original_image_size": struct.unpack(">Q", t[-52:-44])[0],
                "vbmeta_offset": struct.unpack(">Q", t[-44:-36])[0],
                "vbmeta_size": struct.unpack(">Q", t[-36:-28])[0],
            }
        if t[:11] == b"SignerVer02":
            info["samsung_signature_at"] = self.tail_at
        return info


def cmd_info(a):
    t = DtTable.parse(open(a.img, "rb").read())
    h = t.header
    print("image_size   %d" % t.image_size)
    print("total_size   %d  (tail starts here)" % h["total_size"])
    print("entries      %d  page_size %d  version %d" % (h["dt_entry_count"], h["page_size"], h["version"]))
    for i, e in enumerate(t.entries):
        print("  [%d] dt_size %-7d id %#x rev %#x custom %s" %
              (i, len(e["blob"]), e["id"], e["rev"], [hex(c) for c in e["custom"]]))
    print("tail         %d bytes %s" % (len(t.tail), json.dumps(t.avb())))


def cmd_extract(a):
    t = DtTable.parse(open(a.img, "rb").read())
    os.makedirs(a.outdir, exist_ok=False)
    m = {"header": t.header, "image_size": t.image_size, "entries": []}
    for i, e in enumerate(t.entries):
        name = "entry%d.dtb" % i
        open(os.path.join(a.outdir, name), "wb").write(e["blob"])
        m["entries"].append({"file": name, "id": e["id"], "rev": e["rev"], "custom": e["custom"]})
    open(os.path.join(a.outdir, "tail.bin"), "wb").write(t.tail)
    json.dump(m, open(os.path.join(a.outdir, "manifest.json"), "w"), indent=1)


def cmd_roundtrip(a):
    data = open(a.img, "rb").read()
    ok = DtTable.parse(data).build() == data
    print("%s: round-trip %s" % (a.img, "IDENTICAL" if ok else "DIFFERENT"))
    return 0 if ok else 1


def cmd_build(a):
    t = DtTable.parse(open(a.img, "rb").read())
    for spec in a.set:
        idx, path = spec.split("=", 1)
        idx, blob = int(idx), open(path, "rb").read()
        if blob[:4] != b"\xd0\x0d\xfe\xed":
            sys.exit("%s is not an FDT" % path)
        stock = len(t.entries[idx]["blob"])
        if not a.no_pad:
            if len(blob) > stock:
                sys.exit("%s (%d B) is larger than stock entry %d (%d B); use --no-pad" %
                         (path, len(blob), idx, stock))
            blob += b"\0" * (stock - len(blob))
        t.entries[idx]["blob"] = blob
    open(a.out, "wb").write(t.build())
    print("wrote %s (%d bytes)" % (a.out, t.image_size))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest="cmd", required=True)
    x = s.add_parser("info"); x.add_argument("img"); x.set_defaults(f=cmd_info)
    x = s.add_parser("extract"); x.add_argument("img"); x.add_argument("outdir"); x.set_defaults(f=cmd_extract)
    x = s.add_parser("roundtrip"); x.add_argument("img"); x.set_defaults(f=cmd_roundtrip)
    x = s.add_parser("build"); x.add_argument("img"); x.add_argument("out")
    x.add_argument("--set", action="append", default=[], metavar="IDX=FDT")
    x.add_argument("--no-pad", action="store_true"); x.set_defaults(f=cmd_build)
    a = p.parse_args()
    sys.exit(a.f(a) or 0)


if __name__ == "__main__":
    main()

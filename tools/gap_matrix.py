#!/usr/bin/env python3
"""Driver gap matrix: live A50 device-tree compatibles vs. driver coverage.

Usage: gap_matrix.py LIVE_DT_TSV SAMSUNG_TREE TARGET_TREE > matrix.tsv

LIVE_DT_TSV: '#' header lines, then status<TAB>node-path<TAB>compat1|compat2|...
(dumped from /proc/device-tree on the running phone; see docs/06-workflow.md).

Category per enabled node:
  A  exact compatible is handled by a driver in TARGET (works as-is, DT only)
  B  no exact match, but the Samsung driver's source file also exists in
     TARGET (same IP family upstream: add compatible/match data, adapt DT)
  C  Samsung-only driver: must be forward-ported (or replaced) for TARGET
  D  no driver in either tree (data/firmware nodes, sub-nodes, Android nodes)
"""
import os, re, sys

PATS = [re.compile(rb'\.compatible\s*=\s*"([^"]+)"'),
        re.compile(rb'[A-Z_]*_DECLARE\s*\(\s*\w+\s*,\s*"([^"]+)"')]
SCAN = ("drivers", "sound", "arch", "kernel", "mm", "fs", "net", "security", "lib", "block", "crypto", "virt")

def index(tree):
    idx = {}
    for top in SCAN:
        for root, _, files in os.walk(os.path.join(tree, top)):
            for fn in files:
                if fn.endswith((".c", ".h", ".rs")):
                    p = os.path.join(root, fn)
                    try:
                        data = open(p, "rb").read()
                    except OSError:
                        continue
                    for pat in PATS:
                        for m in pat.finditer(data):
                            idx.setdefault(m.group(1).decode(), os.path.relpath(p, tree))
    return idx

def main():
    tsv, sam, tgt = sys.argv[1:4]
    si, ti = index(sam), index(tgt)
    print("cat\tnode\tcompatibles\tsamsung_file\ttarget_match\ttarget_file")
    for line in open(tsv):
        if line.startswith("#"):
            continue
        status, node, compats = line.rstrip("\n").split("\t")
        if status not in ("okay", "ok"):
            continue
        cl = [c for c in compats.split("|") if c]
        sm = next((c for c in cl if c in si), "")
        tm = next((c for c in cl if c in ti), "")
        sf = si.get(sm, "")
        if tm:
            cat = "A"
        elif sf and os.path.exists(os.path.join(tgt, sf)):
            cat = "B"
        elif sf:
            cat = "C"
        else:
            cat = "D"
        print("\t".join([cat, node, "|".join(cl), sf, tm, ti.get(tm, "")]))

if __name__ == "__main__":
    main()

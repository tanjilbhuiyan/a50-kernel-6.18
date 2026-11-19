#!/usr/bin/env python3
"""M9.1: publishable extract of the C4 Wi-Fi block/unblock kernel log.
Keeps only SCSC/WLBT lines, redacts SSIDs, BSSIDs/MACs, IPv4/IPv6 addresses. Usage: redact_c4.py <follow.txt> <out>"""
import re, sys
src, out = sys.argv[1], sys.argv[2]
keep = re.compile(r'wlbt|scsc|mx140|mxman|mxlog|plat_mif|mifqos|srv_message')
subs = [
    (re.compile(r'(ssid )(.+)$'), r'\1<ssid>'),
    (re.compile(r'(slsi_connect: )(.+?)( Freq=)'), r'\1<ssid>\3'),
    (re.compile(r'(?i)\b[0-9a-f*]{2}(:[0-9a-f*]{2}){5}\b'), '<mac>'),
    (re.compile(r'(?i)\b[0-9a-f]{4}(:[0-9a-f]{4}){7}\b'), '<ipv6>'),
    (re.compile(r'(IP: )\d{1,3}(\.\d{1,3}){3}'), r'\1<ipv4>'),
]
lines = []
for l in open(src, errors='replace'):
    if not keep.search(l):
        continue
    for rx, rep in subs:
        l = rx.sub(rep, l)
    lines.append(l)
open(out, 'w').write(''.join(lines))
print(len(lines), 'lines')

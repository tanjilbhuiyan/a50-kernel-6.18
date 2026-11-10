#!/usr/bin/env python3
"""M5.2: download ubuntu.img from the 6.18 backup image, verify it, then end the test.

  backup_ubuntu_img.py OUT_FILE [WAIT_S]

Downloads http://192.168.2.15:5000/ubuntu.img (busybox httpd on the phone,
serving a read-only mount), checks the size, compares sha256 with the phone's own sha256sum over
telnet, and then asks the phone to panic (sysrq c) so the diagnostic dump and
the usual rollback run without waiting for the timer.
"""
import hashlib
import select
import socket
import sys
import time
import urllib.request

out = sys.argv[1]
wait = int(sys.argv[2]) if len(sys.argv) > 2 else 420
HOST, EXPECT = "192.168.2.15", 6442450944


def connect(port, deadline):
    while True:
        try:
            return socket.create_connection((HOST, port), timeout=5)
        except OSError:
            if time.time() > deadline:
                sys.exit(f"no {HOST}:{port}")
            time.sleep(0.5)


connect(5000, time.time() + wait).close()
print(f"{time.strftime('%T')} downloading", flush=True)
h, n, t0 = hashlib.sha256(), 0, time.time()
with urllib.request.urlopen(f"http://{HOST}:5000/ubuntu.img", timeout=60) as r, open(out, "wb") as f:
    print(f"Content-Length: {r.headers.get('Content-Length')}", flush=True)
    while True:
        b = r.read(1 << 20)
        if not b:
            break
        f.write(b)
        h.update(b)
        n += len(b)
dt = time.time() - t0
local = h.hexdigest()
print(f"{time.strftime('%T')} received {n} B in {dt:.0f} s ({n / dt / 1e6:.1f} MB/s), sha256 {local}", flush=True)
if n != EXPECT:
    sys.exit(f"SIZE MISMATCH: {n} != {EXPECT}")

t = connect(23, time.time() + 30)
t.setblocking(False)


def clean(data):
    o, i = bytearray(), 0
    while i < len(data):
        if data[i] == 255 and i + 2 < len(data) and data[i + 1] in (251, 252, 253, 254):
            t.send(bytes([255, 254 if data[i + 1] in (251, 252) else 252, data[i + 2]]))
            i += 3
        elif data[i] == 255 and i + 1 < len(data):
            i += 2
        else:
            o.append(data[i])
            i += 1
    return bytes(o)


def run(cmd, marker, timeout):
    t.send(f"{cmd}; echo {marker}$((1+1))\n".encode())
    buf, end = b"", time.time() + timeout
    while time.time() < end:
        if select.select([t], [], [], 0.5)[0]:
            buf += clean(t.recv(4096))
            if f"{marker}2".encode() in buf:
                break
    return buf.decode(errors="replace")


run("", "WARM", 3)
reply = run("sha256sum /userdata/ubuntu.img", "SUMEND", 1200)
phone = next((w for w in reply.split() if len(w) == 64 and all(c in "0123456789abcdef" for c in w)), None)
print(f"phone sha256 {phone}", flush=True)
ok = phone == local
print("BACKUP VERIFIED" if ok else "BACKUP HASH MISMATCH", flush=True)
run("sync; echo c > /proc/sysrq-trigger", "NEVER", 3)
sys.exit(0 if ok else 1)

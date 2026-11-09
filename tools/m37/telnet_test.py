#!/usr/bin/env python3
"""M3.7 acceptance: telnet to 192.168.2.15 over USB and run read-only commands.

  telnet_test.py OUT_FILE [WAIT_S]

Minimal telnet client (telnetlib is gone from recent Python): refuses every
option. Each command ends with a marker computed on the phone, so a reply over
the network can be told apart from an echo.
"""
import select
import socket
import sys
import time

out = sys.argv[1]
wait = int(sys.argv[2]) if len(sys.argv) > 2 else 300
HOST, PORT = "192.168.2.15", 23
COMMANDS = ["uname -r", "cat /proc/version", "grep userdata /proc/mounts", "ls -l /userdata/ubuntu.img", "ifconfig usb0", "echo $((6*7))"]

deadline = time.time() + wait
while True:
    try:
        s = socket.create_connection((HOST, PORT), timeout=3)
        break
    except OSError:
        if time.time() > deadline:
            sys.exit(f"no telnet at {HOST} within {wait}s")
        time.sleep(0.5)
s.setblocking(False)
print(f"{time.strftime('%T')} connected to {HOST}:{PORT}", flush=True)


def clean(data):
    """Strip telnet commands, refusing each option."""
    out_b, i = bytearray(), 0
    while i < len(data):
        c = data[i]
        if c == 255 and i + 2 < len(data) and data[i + 1] in (251, 252, 253, 254):
            s.send(bytes([255, 254 if data[i + 1] in (251, 252) else 252, data[i + 2]]))
            i += 3
        elif c == 255 and i + 1 < len(data):
            i += 2
        else:
            out_b.append(c)
            i += 1
    return bytes(out_b)


def read_until(marker, timeout):
    buf = b""
    end = time.time() + timeout
    while time.time() < end:
        if select.select([s], [], [], 0.2)[0]:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += clean(chunk)
            if marker and marker in buf:
                return buf, True
    return buf, False


read_until(None, 2)
s.send(b"\n")
read_until(None, 1)
passed = 0
with open(out, "w") as f:
    for i, cmd in enumerate(COMMANDS):
        s.send(f"{cmd}; echo A50END$((2000+{i}))\n".encode())
        data, ok = read_until(f"A50END{2000 + i}".encode(), 8)
        text = data.decode(errors="replace").replace("\r", "")
        f.write(f"$ {cmd}\n{text}\n[{'ok' if ok else 'NO REPLY'}]\n\n")
        print(f"{'ok' if ok else 'NO REPLY'}: {cmd}", flush=True)
        passed += ok
print(f"{time.strftime('%T')} {passed}/{len(COMMANDS)} commands answered", flush=True)
sys.exit(0 if passed == len(COMMANDS) else 1)

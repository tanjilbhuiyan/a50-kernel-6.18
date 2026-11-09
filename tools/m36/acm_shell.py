#!/usr/bin/env python3
"""M3.6 acceptance: run commands over the 6.18 USB ACM shell and save the replies.

  acm_shell.py OUT_FILE [WAIT_S]

Waits for /dev/ttyACM0, then runs read-only commands in the shell the test
init starts on /dev/ttyGS0. Each command ends with a unique marker, so a reply
that came back over USB can be told apart from an echo of what was sent.
"""
import os
import select
import sys
import termios
import time

out = sys.argv[1]
wait = int(sys.argv[2]) if len(sys.argv) > 2 else 240
DEV = "/dev/ttyACM0"
COMMANDS = [
    "uname -r",
    "cat /proc/version",
    "cat /sys/class/udc/*/state",
    "cat /sys/class/udc/*/current_speed",
    "cat /proc/uptime",
    "echo $((6*7))",
]


def read_until(fd, marker, timeout):
    data = b""
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            data += chunk
            if marker in data:
                return data, True
    return data, False


deadline = time.time() + wait
while not os.path.exists(DEV):
    if time.time() > deadline:
        sys.exit(f"{DEV} did not appear within {wait}s")
    time.sleep(0.2)
time.sleep(2)

for attempt in range(40):  # udev may apply the permissions just after the node appears
    try:
        fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)
        break
    except PermissionError:
        if attempt == 39:
            raise
        time.sleep(0.5)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[3] = 0
attrs[6][termios.VMIN] = 0
attrs[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, attrs)
print(f"{time.strftime('%T')} opened {DEV}", flush=True)
read_until(fd, b"\0never\0", 1)
os.write(fd, b"\n")
read_until(fd, b"\0never\0", 1)

passed = 0
with open(out, "w") as f:
    for i, cmd in enumerate(COMMANDS):
        # The marker is built by the shell, so the echoed command line cannot match it.
        os.write(fd, f'{cmd}; echo A50END$((1000+{i}))\n'.encode())
        marker = f"A50END{1000 + i}".encode()
        data, ok = read_until(fd, marker, 8)
        text = data.decode(errors="replace").replace("\r", "")
        f.write(f"$ {cmd}\n{text}\n[{'ok' if ok else 'NO REPLY'}]\n\n")
        print(f"{'ok' if ok else 'NO REPLY'}: {cmd}", flush=True)
        passed += ok
print(f"{time.strftime('%T')} {passed}/{len(COMMANDS)} commands answered", flush=True)
sys.exit(0 if passed == len(COMMANDS) else 1)

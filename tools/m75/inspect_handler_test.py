#!/usr/bin/env python3
"""Check fd decoding, socket identity, environment output and owned-child cleanup."""
import importlib.util
import os
from pathlib import Path
import socket
import struct
import sys
import tempfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('handler_probe', Path(__file__).with_name('inspect_handler.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

data = struct.pack('<ihhihh', 5, 1, 0, 8, 4, 8)
assert probe.pollfds(data, 2) == [
    {'fd': 5, 'events': '0x1', 'revents': '0x0'},
    {'fd': 8, 'events': '0x4', 'revents': '0x8'}]
for raw, count in ((b'', 0), (data, 65), (data[:-1], 2)):
    try:
        probe.pollfds(raw, count)
    except ValueError:
        pass
    else:
        raise AssertionError('invalid pollfd input accepted')
print('PASS: native pollfd layout/events and bounded short/oversized rejection')

rows = probe.unix_rows('Num RefCount Protocol Flags Type St Inode Path\n'
                       '000: 2 0 00010000 0001 01 123 /run/mir_socket\n'
                       '001: 2 0 00000000 0001 03 124\n')
assert rows['123']['bound_path'] == '/run/mir_socket'
assert rows['124']['bound_path'] is None
left, right = socket.socketpair()
try:
    detail = probe.socket_details(left.fileno())
    assert detail['peer_credentials']['pid'] == os.getpid()
    # Read-only duplication must leave the original socket usable.
    right.send(b'x')
    assert left.recv(1) == b'x'
finally:
    left.close()
    right.close()
print('PASS: named/anonymous socket distinction and non-consuming peer query')

env = probe.environment(b'QT_QPA_PLATFORM=ubuntumirclient;wayland-egl;xcb\0PRIVATE_TEST_TOKEN=secret\0HOME=/home/phablet\0')
visible = probe.visible_environment(env)
assert visible['QT_QPA_PLATFORM'] == 'ubuntumirclient;wayland-egl;xcb'
assert 'PRIVATE_TEST_TOKEN' not in visible
print('PASS: display selection preserved and unrelated environment omitted')

with tempfile.TemporaryDirectory(prefix='a50-handler-test-') as tmp:
    output = Path(tmp) / 'child.log'
    program = ('import subprocess,sys,time; '
               'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); '
               'print(p.pid,flush=True); time.sleep(60)')
    result = probe.bounded_child([sys.executable, '-c', program], os.environ.copy(),
                                 os.getuid(), os.getgid(), os.getgroups(), output, 0.5)
    assert result['timeout'] and result['returncode'] < 0
    descendant = int(output.read_text().strip())
    for pid in (result['pid'], descendant):
        status = Path('/proc') / str(pid) / 'status'
        assert not status.exists() or '\nState:\tZ' in status.read_text(), 'diagnostic child still running'
    os.kill(os.getpid(), 0)
    # Also cover a process that exits normally before the limit.
    result = probe.bounded_child([sys.executable, '-c', 'print("ok")'], os.environ.copy(),
                                 os.getuid(), os.getgid(), os.getgroups(), output, 2)
    assert not result['timeout'] and result['returncode'] == 0 and output.read_text().strip() == 'ok'
print('PASS: timeout kills only the owned child group; normal child completion preserved')

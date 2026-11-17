#!/usr/bin/env python3
"""Watch for the test's USB NIC, provision transient DHCP if needed, prove SSH.

Usage: watch_ssh.py OUTPUT [WAIT_SECONDS]
Only a newly detected USB network interface is eligible. The SSH host key is
checked against the already trusted baseline's Wi-Fi alias. No auth changes.
"""
import json
from pathlib import Path
import socket
import subprocess
import sys
import time

out = Path(sys.argv[1])
deadline = time.monotonic() + (int(sys.argv[2]) if len(sys.argv) > 2 else 230)
seen = {}
configured = set()
profile_name = 'a50-m54-usb'
endpoint = '10.15.19.82'
command = '''printf 'A50M54_UNAME='; uname -r
systemctl is-system-running
systemctl --failed --no-pager --plain --no-legend
lxc-info -n android
ip -brief address show usb0
findmnt -no TARGET,OPTIONS /userdata
cat /sys/class/udc/*/state
'''


def run(args, timeout=8):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def usb_interface(name):
    device = Path('/sys/class/net') / name / 'device'
    return device.exists() and '/usb' in str(device.resolve())


while time.monotonic() < deadline:
    for nic in sorted(Path('/sys/class/net').iterdir()):
        name = nic.name
        if not usb_interface(name):
            continue
        if name not in seen:
            seen[name] = time.monotonic()
            print(f'{time.strftime("%T")} USB NIC {name}', flush=True)
        route = run(['ip', '-j', 'route', 'get', endpoint])
        routes = json.loads(route.stdout) if route.returncode == 0 else []
        if not routes or routes[0].get('dev') != name:
            if time.monotonic() - seen[name] > 8 and name not in configured:
                configured.add(name)
                # Avoid touching an existing connection with our chosen name.
                existing = run(['nmcli', '-g', 'connection.id', 'con', 'show', profile_name])
                if existing.returncode == 0:
                    print('Profile name already exists; no host change made', flush=True)
                    continue
                try:
                    created = run(['nmcli', 'con', 'add', 'save', 'no', 'type', 'ethernet',
                                   'con-name', profile_name, 'ifname', name,
                                   'ipv4.method', 'auto', 'ipv6.method', 'disabled'])
                except subprocess.TimeoutExpired:
                    print('NetworkManager setup timed out; host authorization may be needed', flush=True)
                    continue
                print('Temporary DHCP profile: ' + created.stdout.strip() + created.stderr.strip(), flush=True)
                if created.returncode == 0:
                    uuid = run(['nmcli', '-g', 'connection.uuid', 'con', 'show', profile_name]).stdout.strip()
                    out.with_suffix('.profile-uuid').write_text(uuid + '\n')
                    try:
                        up = run(['nmcli', '--wait', '5', 'con', 'up', 'uuid', uuid, 'ifname', name])
                        print(up.stdout.strip() + up.stderr.strip(), flush=True)
                    except subprocess.TimeoutExpired:
                        print('DHCP activation still pending; continuing to watch', flush=True)
            continue
        for port, user in ((22, 'root'), (8022, 'phablet')):
            try:
                with socket.create_connection((endpoint, port), timeout=1):
                    pass
                reply = run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3',
                             '-o', 'StrictHostKeyChecking=yes',
                             '-o', 'HostKeyAlias=192.168.0.171', '-p', str(port),
                             user + '@' + endpoint, command], timeout=15)
            except (OSError, subprocess.TimeoutExpired):
                continue
            if 'A50M54_UNAME=6.18.' in reply.stdout:
                text = (f'USB interface: {name}\nRoute: {route.stdout.strip()}\n'
                        f'SSH: {user}@{endpoint}:{port}; known host alias 192.168.0.171\n'
                        + reply.stdout + reply.stderr)
                out.write_text(text)
                print(f'{time.strftime("%T")} VERIFIED SSH on 6.18 through USB {name}, port {port}', flush=True)
                sys.exit(0)
    time.sleep(1)
sys.exit('No verified 6.18 USB SSH session before deadline')

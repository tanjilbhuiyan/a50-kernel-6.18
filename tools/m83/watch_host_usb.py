#!/usr/bin/env python3
"""Read-only A50 USB device/ancestor power sampling. Never read serials or payloads."""
import argparse
import json
from pathlib import Path
import time

IDS = {('04b9', '0afe'), ('04e8', '685d'), ('1209', '0004')}
ATTRS = ('idVendor', 'idProduct', 'devnum', 'speed', 'power/control',
         'power/runtime_status', 'power/runtime_active_time',
         'power/runtime_suspended_time', 'power/autosuspend_delay_ms',
         'power/wakeup')


def read(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return None


def sample(ancestors):
    nodes = {}
    for device in sorted(Path('/sys/bus/usb/devices').glob('*')):
        if ':' in device.name:
            continue
        if (read(device / 'idVendor'), read(device / 'idProduct')) not in IDS:
            continue
        nodes[str(device)] = {a: read(device / a) for a in ATTRS}
        for parent in device.resolve().parents:
            # Root hub and its xHCI PCI controller; no global host policy change.
            if (parent.name.startswith('usb') and parent.name[3:].isdigit()
                    or read(parent / 'class') == '0x0c0330'):
                ancestors.add(parent)
    for parent in sorted(ancestors):
        nodes[str(parent)] = {a: read(parent / a) for a in ATTRS}
    return nodes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('stop_file', type=Path)
    parser.add_argument('--seconds', type=int, default=1200)
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    ancestors = set()
    deadline = time.monotonic() + args.seconds
    with args.output.open('x') as output:
        while time.monotonic() < deadline and not args.stop_file.exists():
            output.write(json.dumps({'wall_time': time.time(),
                                     'monotonic': time.monotonic(),
                                     'nodes': sample(ancestors)}) + '\n')
            output.flush()
            if args.once:
                break
            time.sleep(1)


if __name__ == '__main__':
    main()

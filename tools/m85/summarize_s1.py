#!/usr/bin/env python3
"""Summarize published M8.5 S1 evidence without phone access or source changes."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PREFIX = ROOT / 'reference/m85-integration/s1'


def read(name):
    return Path(str(PREFIX) + '-' + name).read_text()


def main():
    soak = read('soak.txt')
    samples = []
    for m in re.finditer(r'M85_S1_SAMPLE target=(\d+) uptime=([\d.]+)\n(.*?)(?=\nM85_S1_|\Z)', soak, re.S):
        text = m[3]
        display = re.search(r'^display: (.+)', text, re.M)[1]
        values = dict(re.findall(r'(\w+)=(\S+)', display))
        dma = re.search(r'dmabuf: Total (\d+) objects, (\d+) bytes', text)
        ui = re.search(r'ui: unit=(\S+) pid=(\d+) fds=(\d+) VmRSS:\s*(\d+) kB threads=(\d+)', text)
        samples.append({'target': int(m[1]), 'uptime': float(m[2]), 'display': values,
                        'mem_available_kib': int(re.search(r'MemAvailable:\s*(\d+)', text)[1]),
                        'dma_objects': int(dma[1]), 'dma_bytes': int(dma[2]),
                        'ui_unit': ui[1], 'ui_pid': int(ui[2]), 'ui_fds': int(ui[3]),
                        'ui_rss_kib': int(ui[4]), 'faults': int(re.search(r'^faults=(\d+)', text, re.M)[1]),
                        'failed_units': int(re.search(r'NFailedUnits=(\d+)', text)[1]),
                        'system_state': re.search(r'SystemState=(\S+)', text)[1]})
    assert len(samples) == 25 and samples[0]['target'] == 120 and samples[-1]['target'] == 840
    regressions = {k: int(v) for k, v in re.findall(r'M85_S1_((?:KBASE_MEMORY|ION)_\d+)_RC=(\d+)', soak)}
    assert len(regressions) == 4 and not any(regressions.values())
    keys = read('keys.txt')
    counts = {str(code): {str(value): len(re.findall(r'type 1 code ' + str(code) + r' value ' + str(value), keys))
                         for value in (0, 1, 2)} for code in (114, 115, 116)}
    for c in counts.values():
        assert c['0'] == c['1'] and c['1'] > 0 and not c['2']
    touch = read('touch.txt')
    assert ' type ' not in touch and 'x_range=' not in touch and 'y_range=' not in touch
    touch_counts = [int(v) for v in re.findall(r'summary contacts=(\d+)', touch)]
    assert len(touch_counts) == 3 and sum(touch_counts) > 0
    trace = read('usb-trace.txt')
    stats = read('trace-stats.txt')
    loss = {name: [int(x) for x in re.findall('^' + name + ': (\\d+)', stats, re.M)]
            for name in ('overrun', 'commit overrun', 'dropped events')}
    assert all(len(v) == 8 and not any(v) for v in loss.values())
    assert 'A50M85USB_START' in trace and 'A50M85USB_END' in trace
    host = read('host-usb.txt').splitlines()
    start = next(i for i, line in enumerate(host) if 'idVendor=1209' in line)
    port = re.search(r'usb (\S+):', host[start])[1]
    end = next(i for i, line in enumerate(host[start:], start) if f'usb {port}:' in line and 'idVendor=04e8' in line)
    runtime = host[start:end]
    disconnects = [line for line in runtime if f'usb {port}: USB disconnect' in line]
    assert disconnects  # Last one led to the timed Download enumeration.
    owner = json.loads((PREFIX.parent / 'owner-observations.json').read_text())
    assert owner['minimum_window_seconds'] >= 600
    assert any(o['response'].startswith('Responsive throughout; apps closed; back at Home.') for o in owner['observations'])
    fault_lines = [line for line in read('kernel-events.txt').splitlines() if re.search(
        r'Unable to handle|SError|Internal error|BUG:|Kernel panic|WARNING: CPU|kbase.*(?:fault|error)|sysmmu.*fault|dma_fence.*timed out', line)]
    assert not fault_lines and not any(s['faults'] for s in samples)
    assert all(int(s['display'][key]) == 0 for s in samples for key in
               ('copied', 'dma_fallbacks', 'skipped', 'acq_timeouts'))
    assert len({s['ui_pid'] for s in samples}) == 1 and not any(s['failed_units'] for s in samples)
    run = read('run.txt')
    assert 'PRE-FLIGHT: ALL CHECKS PASSED' in run
    fsck = read('baseline-fsck.txt').strip()
    assert ': clean,' in fsck
    inputs = json.loads(read('inputs.json'))
    for name, record in inputs['files'].items():
        data = (ROOT / name).read_bytes()
        assert len(data) == record['size'] and hashlib.sha256(data).hexdigest() == record['sha256'], name
    first, last = samples[0], samples[-1]
    summary = {'test': 'M8.5 S1', 's3': 'touch and key delivery pass; power screen action remains deferred to M12',
               'interactive_window_min_seconds': owner['minimum_window_seconds'],
               'owner_responsive_throughout': True, 'sample_count': len(samples),
               'sample_duration_seconds': round(last['uptime'] - first['uptime'], 2),
               'regressions': regressions, 'key_press_release_counts': counts,
               'touch_contacts_by_window': touch_counts, 'raw_touch_coordinates_saved': False,
               'ui_pids': sorted({s['ui_pid'] for s in samples}), 'kernel_fault_signatures': fault_lines,
               'system_state_final': last['system_state'], 'failed_units_max': max(s['failed_units'] for s in samples),
               'dma_scanout_first_last': [int(first['display']['scanned']), int(last['display']['scanned'])],
               'display_copy_fallback_skip_acquire_timeouts': 0,
               'memory': {'first': first, 'last': last,
                          'dma_objects_max': max(s['dma_objects'] for s in samples),
                          'dma_bytes_max': max(s['dma_bytes'] for s in samples),
                          'ui_fds_max': max(s['ui_fds'] for s in samples),
                          'ui_rss_kib_max': max(s['ui_rss_kib'] for s in samples),
                          'mem_available_kib_min': min(s['mem_available_kib'] for s in samples)},
               'memory_limit': 'Some reclamation observed, but DMA-BUF and UI memory remain above startup. App set varied; short post-close window does not prove leak freedom. Fixed-workload retention follow-up remains warranted.',
               'hall_events': 'not exercised: no magnet/magnetic cover available',
               'usb_extra_disconnects': disconnects[:-1], 'normal_timed_reset_disconnect': disconnects[-1],
               'usb_device_events': [l.strip() for l in trace.splitlines() if 'dwc3_event:' in l],
               'usb_requested_disconnect_events': [l.strip() for l in trace.splitlines() if re.search(
                   r'usb_gadget_(?:disconnect|deactivate|vbus_disconnect):', l)],
               'trace_losses': loss, 'usb_cause': 'unresolved; captured suspend/bus-reset sequence, no observed explicit gadget disconnect call',
               'restored_at': re.search(r'\[([\d:]+)\] rolled back', run)[1],
               'baseline_booted_at': re.search(r'up since ([\d-]+ [\d:]+)', run)[1],
               'postflight': 'passed', 'fsck': fsck, 'inputs_reverified': len(inputs['files']),
               'M8_complete': False,
               'remaining': ['physical hall event check', 'shared USB issue disposition', 'recorded memory retention follow-up']}
    Path(str(PREFIX) + '-samples.json').write_text(json.dumps(samples, indent=2) + '\n')
    Path(str(PREFIX) + '-results.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({k: v for k, v in summary.items() if k not in ('memory', 'trace_losses', 'usb_device_events')}, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""M10.3 B2h: the stock mixer settings for the earpiece (handset) tone, from the vendor XMLs.

Output (stdout): one 'NAME<TAB>VALUE' line per control, in apply order:
  1. the top-level defaults of vendor mixer_paths.xml (what the HAL sets at start),
  2. path "media-handset" (dev-handset + route-sifs0-to-uaif0), expanded,
  3. path "gain-media-handset" of mixer_gains.xml.
Changes from the XML, each listed in EXCEPTIONS with its reason. Controls the 6.18 card lacks are skipped on the
phone and logged. No amplifier (TFA) control is written: TFA stays probe-only and UAIF2 is not routed.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / 'reference/m10-audio/vendor-etc'

# name -> replacement value (None = do not write)
EXCEPTIONS = {
    # Stock writes 31 to a 0..15 field; the 4.14 put masked it to 15 (0 dB). 6.18 rejects out-of-range values.
    'Mono Playback Volume': '15',
    # "Stereo DAC Mixer" is not an item in either driver (stock or mainline): on stock the HAL's write fails and the
    # register keeps item 0, "Stereo1 DAC Mixer". Write that item explicitly (headset path only).
    'DAC L1 Source': 'Stereo1 DAC Mixer',
    'DAC R1 Source': 'Stereo1 DAC Mixer',
    # Absent on 6.18 (Samsung-only codec extension / debug helper / unwired machine switches); skip explicitly.
    'Disable NG2': None,
    'Debug Buffer Switch': None,
    'Main Mic Switch': None,
    'Sub Mic Switch': None,
    'Headset Mic Switch': None,
}


def paths(root):
    return {p.get('name'): p for p in root.findall('path')}


def expand(path, table, out):
    for el in path:
        if el.tag == 'ctl':
            out.append((el.get('name'), el.get('value')))
        elif el.tag == 'path':
            expand(table[el.get('name')], table, out)


def main():
    mp = ET.parse(VENDOR / 'mixer_paths.xml').getroot()
    mg = ET.parse(VENDOR / 'mixer_gains.xml').getroot()
    table = paths(mp)
    gains = paths(mg)
    out = [(c.get('name'), c.get('value')) for c in mp.findall('ctl')]
    expand(table['media-handset'], table, out)
    expand(gains['gain-media-handset'], gains, out)
    for name, value in out:
        if name in EXCEPTIONS:
            value = EXCEPTIONS[name]
            if value is None:
                continue
        assert 'tfa' not in name.lower() and 'calib' not in name.lower(), name
        assert '\t' not in name and '\n' not in name and "'" not in name + value, name
        sys.stdout.write(f'{name}\t{value}\n')


if __name__ == '__main__':
    main()

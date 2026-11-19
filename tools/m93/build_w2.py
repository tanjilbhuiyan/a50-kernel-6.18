#!/usr/bin/env python3
"""Build M9.3 W2: H1 source/config + the WLBT core + the SCSC Wi-Fi driver (branch a50-m92-w1-test) + firmware path.

Config delta from H1: CONFIG_SCSC_* (core, Exynos 9610 platform, NULL-service test client; no auto-start:
the collector boots the chip by writing 1 to /dev/mx_client_test_0) and firmware_class.path=/vendor/firmware,/vendor/etc/wifi appended to the built-in command line.
DTB = H1 DTB plus the WLBT nodes; runtime cpio = I4. Never flashes.
"""
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
import sys

TAG = sys.argv[1] if len(sys.argv) > 1 else 'w2'
EXTRA = ' ' + sys.argv[2] if len(sys.argv) > 2 else ''  # extra built-in cmdline words (diagnostics)
ROOT = Path(__file__).resolve().parents[2]
KERNEL = ROOT / 'src/m92/test-kernel'
OUT = ROOT / f'src/m93/{TAG}-out'
SCSC = {'CONFIG_SCSC_CORE': 'y', 'CONFIG_SCSC_PLATFORM_EXYNOS9610': 'y', 'CONFIG_SCSC_CM_MX_CLIENT_TEST': 'y',
        'CONFIG_SCSC_WLBT_CONFIG_PLATFORM': '"leman_s620_univ"',
        'CONFIG_SCSC_CORE_FW_LOCATION': '"/vendor/etc/wifi"', 'CONFIG_SCSC_CORE_TOOL_LOCATION': '"/vendor/bin"',
        'CONFIG_RFKILL': 'y', 'CONFIG_CFG80211': 'y', 'CONFIG_SCSC_WLAN': 'y', 'CONFIG_SCSC_WLAN_MAX_INTERFACES': '3',
        'CONFIG_SCSC_AP_INTERFACE_NAME': '"swlan0"',
        # off: unrelated GKI wireless defaults
        'CONFIG_MAC80211': 'n', 'CONFIG_ATH6KL': 'n', 'CONFIG_BRCMFMAC': 'n', 'CONFIG_MWIFIEX': 'n',
        'CONFIG_VIRT_WIFI': 'n', 'CONFIG_NL80211_TESTMODE': 'n'}
# Mainline forces CFG80211_REQUIRE_SIGNED_REGDB (unless CERTIFICATION_ONUS); it selects the keyring/X.509 stack.
DERIVED = ('CONFIG_CFG80211_', 'CONFIG_RFKILL_', 'CONFIG_WLAN_VENDOR_SAMSUNG', 'CONFIG_SCSC_WLAN_WES_NCHO',
           'CONFIG_ASN1', 'CONFIG_ASYMMETRIC_', 'CONFIG_CRYPTO_AKCIPHER', 'CONFIG_CRYPTO_RSA', 'CONFIG_CRYPTO_SIG',
           'CONFIG_FIPS_SIGNATURE_SELFTEST', 'CONFIG_OID_REGISTRY', 'CONFIG_PKCS7_', 'CONFIG_PKCS8_',
           'CONFIG_SECONDARY_TRUSTED_KEYRING', 'CONFIG_SIGNED_PE_FILE_VERIFICATION', 'CONFIG_SYSTEM_DATA_VERIFICATION',
           'CONFIG_SYSTEM_EXTRA_CERTIFICATE', 'CONFIG_SYSTEM_TRUSTED_KEYRING', 'CONFIG_SYSTEM_TRUSTED_KEYS',
           'CONFIG_X509_CERTIFICATE_PARSER')
FW_PATH = ' firmware_class.path=/vendor/firmware,/vendor/etc/wifi'


def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def values(text):
    pairs = {}
    for line in text.splitlines():
        if line.startswith('CONFIG_'):
            k, v = line.split('=', 1)
            pairs[k] = v
        elif re.fullmatch(r'# CONFIG_\w+ is not set', line):
            pairs[line.split()[1]] = 'n'
    return pairs


def main():
    assert not OUT.exists(), 'Choose a fresh output; refusing overwrite'
    assert subprocess.check_output(['git', '-C', KERNEL, 'branch', '--show-current'], text=True).strip() == 'a50-m92-w1-test'
    assert not subprocess.check_output(['git', '-C', KERNEL, 'status', '--porcelain'], text=True)
    source = subprocess.check_output(['git', '-C', KERNEL, 'rev-parse', 'HEAD'], text=True).strip()
    run('python3', '-I', ROOT / 'tools/m75/make_i4_runtime.py', stdout=subprocess.DEVNULL)
    h1 = (ROOT / 'src/m84/h1-as-built/.config').read_text()
    m = re.search(r'^CONFIG_CMDLINE="([^"]*)"$', h1, re.M)
    assert m and 'firmware_class' not in m.group(1)
    seed = h1.replace(m.group(0), 'CONFIG_CMDLINE="%s%s%s"' % (m.group(1), FW_PATH, EXTRA))
    seed += ''.join(('# %s is not set\n' % k) if v == 'n' else ('%s=%s\n' % (k, v)) for k, v in SCSC.items())
    OUT.mkdir(parents=True)
    (ROOT / 'src/m93').mkdir(exist_ok=True)
    (OUT / '.config').write_text(seed)
    ack = ROOT / 'src/ack-6.18'
    clang = ack / 'prebuilts/clang/host/linux-x86/clang-r584948c'
    shim = OUT / 'shim'
    shim.mkdir()
    (shim / 'bc').symlink_to(ack / 'prebuilts/build-tools/linux-x86/bin/gavinhoward-bc')
    env = os.environ.copy()
    for key in ('LOCALVERSION', 'KCONFIG_CONFIG', 'KCONFIG_ALLCONFIG', 'KBUILD_OUTPUT',
                'KCFLAGS', 'KCPPFLAGS', 'KRUSTFLAGS', 'KBUILD_EXTRA_SYMBOLS'):
        env.pop(key, None)
    env.update(PATH=os.pathsep.join(map(str, (shim, clang / 'bin',
        ack / 'prebuilts/kernel-build-tools/linux_musl-x86/bin',
        ack / 'prebuilts/build-tools/linux-x86/bin'))) + os.pathsep + env['PATH'],
        LIBCLANG_PATH=str(clang / 'lib'), KBUILD_BUILD_TIMESTAMP='Wed Nov  4 00:00:00 UTC 2026',
        KBUILD_BUILD_USER='a50', KBUILD_BUILD_HOST='firstlight',
        KBUILD_BUILD_VERSION='1', SOURCE_DATE_EPOCH='1793750400')
    make = ['make', '-C', KERNEL, '-j16', 'ARCH=arm64', 'LLVM=1', f'O={OUT}',
            f'RUSTC={ack / "prebuilts/rust-toolchain/linux-x86/1.91.1.p3/bin/rustc"}',
            f'BINDGEN={ack / "prebuilts/clang-tools/linux-x86/bin/bindgen"}']
    run(*make, 'olddefconfig', env=env)
    old, new = values(h1), values((OUT / '.config').read_text())
    delta = {k: [old.get(k), new.get(k)] for k in old.keys() | new.keys() if old.get(k) != new.get(k)}
    expected = set(SCSC) | {'CONFIG_CMDLINE', 'CONFIG_SCSC_MX_ALWAYS_ON'}
    assert new.get('CONFIG_SCSC_MX_ALWAYS_ON') == 'n'
    derived = {k for k in set(delta) - expected if k.startswith(DERIVED)}
    unexpected = set(delta) - derived - expected
    assert not unexpected, sorted(unexpected)
    for k, v in SCSC.items():
        assert new.get(k, 'n') == v, (k, new.get(k))
    assert new['CONFIG_CMDLINE'].endswith(FW_PATH + EXTRA + '"')
    run('python3', '-I', ROOT / 'tools/m52/guard_unittest.py', KERNEL, '0x1c8700', '0xee42ff')
    run('python3', '-I', ROOT / 'tools/m53/sense_unittest.py', KERNEL)
    run(*make, 'Image', 'exynos/exynos9610-a50-gpu.dtb', env=env)
    dtb = OUT / 'arch/arm64/boot/dts/exynos/exynos9610-a50-gpu.dtb'
    assert hashlib.sha256((OUT / 'usr/initramfs_data.cpio').read_bytes()).hexdigest() == \
        '2970e1aa2366a1ede69fb22a83a66c3d59361e53a05fbebe095a6f9ab25484ae', 'runtime cpio differs from I4'
    boot = ROOT / f'src/m93/boot-{TAG}.img'
    dtimg = ROOT / f'src/m93/dt-{TAG}.img'
    run('bash', ROOT / 'tools/m22_pack.sh', OUT / 'arch/arm64/boot/Image', boot)
    run('python3', '-I', ROOT / 'tools/dt_table.py', 'build', ROOT / 'reference/stock-images/dt.img', dtimg,
        '--set', f'0={dtb}')
    files = [OUT / '.config', OUT / 'arch/arm64/boot/Image', dtb, OUT / 'usr/initramfs_data.cpio', boot, dtimg]
    result = {'source_commit': source, 'config_delta_from_H1': delta,
              'files': {str(p.relative_to(ROOT)): {'size': p.stat().st_size,
                        'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files}}
    (ROOT / 'reference/m93-wifi').mkdir(parents=True, exist_ok=True)
    (ROOT / f'reference/m93-wifi/{TAG}-build-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""M5.1: build scripts/config flags from the Halium checker, for options that exist in 6.18.

  gen_halium_flags.py CHECKER KERNEL_TREE OUT_FLAGS

Options the checker wants on become -e, options it wants off become -d,
options that 6.18 renamed get their 6.18 name (MAP), and options that no
longer exist are only listed.
"""
import os
import re
import sys

checker, tree, out = sys.argv[1:4]
script = open(checker).read()


def lst(name):
    m = re.search(name + r'="\n(.*?)"', script, re.S)
    return m.group(1).split() if m else []


known = set()
for root, _, files in os.walk(tree):
    if "/.git" in root:
        continue
    for f in files:
        if f.startswith("Kconfig"):
            known.update(re.findall(r"^\s*(?:menu)?config\s+(\w+)", open(os.path.join(root, f), errors="replace").read(), re.M))

# Checker name -> 6.18 name (renamed or merged upstream).
MAP = {
    "AUTOFS4_FS": "AUTOFS_FS",
    "CGROUP_MEM_RES_CTLR": "MEMCG",
    "CGROUP_MEM_RES_CTLR_SWAP": "MEMCG",
    "CGROUP_MEM_RES_CTLR_KMEM": "MEMCG",
    "CC_STACKPROTECTOR": "STACKPROTECTOR",
    "DEBUG_RODATA": "STRICT_KERNEL_RWX",
    "IOSCHED_DEADLINE": "MQ_IOSCHED_DEADLINE",
    "AUDIT_TREE": "AUDITSYSCALL",
    "AUDIT_WATCH": "AUDITSYSCALL",
    "NETFILTER_TPROXY": "NETFILTER_XT_TARGET_TPROXY",
}
flags, gone = [], []
for c in lst("CONFIGS_ON"):
    n = MAP.get(c[7:], c[7:])
    (flags.append(f"-e {n}") if n in known else gone.append(c[7:] + " (on)"))
for c in lst("CONFIGS_OFF"):
    n = c[7:]
    (flags.append(f"-d {n}") if n in known else gone.append(n + " (off)"))
# Prerequisites the checker does not list, so olddefconfig keeps the options it does list,
# plus BLK_DEV_LOOP from docs/03-kernel-contract.md (Ubuntu Touch mounts ubuntu.img through loop).
DEPS = ["NETFILTER_ADVANCED", "NF_CONNTRACK", "NETFILTER_XTABLES", "IP_NF_IPTABLES", "IPV6",
        "IP6_NF_IPTABLES", "NF_CONNTRACK_MARK", "NF_CONNTRACK_SECMARK", "NETWORK_SECMARK",
        "NEW_LEDS", "LEDS_CLASS", "LEDS_TRIGGERS", "PERF_EVENTS", "DEVMEM", "HID", "BT_BREDR",
        "NF_TPROXY_IPV4", "NF_TPROXY_IPV6", "RTC_CLASS", "BLK_DEV", "BLK_DEV_LOOP",
        "NETFILTER_XTABLES_LEGACY", "IP_NF_IPTABLES_LEGACY", "IP6_NF_IPTABLES_LEGACY",
        "IP_NF_MANGLE", "IP6_NF_MANGLE", "HID_SUPPORT", "HID"]
for n in DEPS:
    if n in known:
        flags.insert(0, f"-e {n}")
# DEFAULT_SECURITY is gone in 6.18; CONFIG_LSM sets the order, AppArmor before the other major LSMs.
flags.append('--set-str LSM landlock,lockdown,yama,loadpin,safesetid,integrity,apparmor,selinux,smack,tomoyo,bpf')
seen, uniq = set(), []
for f in flags:
    if f not in seen:
        seen.add(f)
        uniq.append(f)
open(out, "w").write("\n".join(uniq) + "\n")
print(f"{len(uniq)} flags; not in 6.18: {' '.join(gone)}")

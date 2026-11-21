#!/usr/bin/env python3
"""Compile the real ABOX TFA window/reply functions with host IRQ/memory stubs.

Checks malformed sizes/replies, unmapped windows, late/duplicate responses and
the read buffer bounds. This does not simulate firmware, locking or DMA.
Usage: python3 -I tools/m10/sync_ipc_unittest.py KERNEL
"""
import re
import resource
import subprocess
import sys
import tempfile
from pathlib import Path


def function(source, name):
    match = re.search(r"(?ms)^static [^;{}]+\b" + name + r"\([^;{}]*\)\s*\{.*?^\}", source)
    assert match, name
    return match[0]


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    kernel = Path(sys.argv[1])
    source = (kernel / "sound/soc/samsung/abox/abox_synchronized_ipc.c").read_text()
    context = re.search(r"(?ms)^struct abox_tfa_sync \{.*?^\};", source)[0]
    constants = "\n".join(re.findall(r"(?m)^#define TFA_.*$", source))
    bodies = function(source, "abox_tfa_window") + "\n" + function(source, "abox_tfa_reply")
    prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint8_t u8;
typedef uint32_t u32;
typedef int irqreturn_t;
typedef int spinlock_t;
struct device { int dummy; };
struct abox_data { int dummy; };
struct mutex { int dummy; };
struct completion { int done; };
#define SZ_8K 8192
#define IRQ_NONE 0
#define IRQ_HANDLED 1
#define IPC_ERAP 7
#define REALTIME_EXTRA 0xea
#define ERR_PTR(e) ((void *)(intptr_t)(e))
#define IS_ERR(p) ((uintptr_t)(p) >= (uintptr_t)-4095)
#define IS_ERR_OR_NULL(p) (!(p) || IS_ERR(p))
#define PTR_ERR(p) ((intptr_t)(p))
#define spin_lock_irqsave(lock, flags) ((flags) = 0)
#define spin_unlock_irqrestore(lock, flags) ((void)(flags))
#define rmb() ((void)0)
static void complete(struct completion *c) { c->done++; }
typedef struct {
    struct { struct {
        int msgtype;
        struct { struct { u32 params[4]; } raw; } param;
    } erap; } msg;
} ABOX_IPC_MSG;
static unsigned char shared[8192];
static bool mapped = true;
static void *abox_addr_to_kernel_addr(struct abox_data *data, unsigned int addr)
{
    (void)data;
    if (!mapped || addr < 0x80584000 || addr >= 0x80586000)
        return ERR_PTR(-EFAULT);
    return shared + addr - 0x80584000;
}
'''
    tests = r'''
static struct abox_tfa_sync state;
static ABOX_IPC_MSG packet;
static void setup(unsigned expected, unsigned reported)
{
    memset(&state, 0, sizeof(state));
    memset(&packet, 0, sizeof(packet));
    memset(shared, 0x5a, sizeof(shared));
    memset(state.read_buffer, 0xa5, sizeof(state.read_buffer));
    mapped = true;
    state.pending = true;
    state.expected_reply = TFA_RES_READ;
    state.expected_bytes = expected;
    packet.msg.erap.msgtype = REALTIME_EXTRA;
    packet.msg.erap.param.raw.params[0] = TFA_RES_READ;
    packet.msg.erap.param.raw.params[1] = reported;
}
static void reply(void) { assert(abox_tfa_reply(IPC_ERAP, &state, &packet) == IRQ_HANDLED); }
static void no_copy(void) {
    for (unsigned i = 0; i < sizeof(state.read_buffer); i++)
        assert(state.read_buffer[i] == 0xa5);
}
int main(void)
{
    setup(16, 16); reply();
    assert(state.result == 0 && !state.pending && state.reply.done == 1);
    for (unsigned i = 0; i < 16; i++) assert(state.read_buffer[i] == 0x5a);
    assert(state.read_buffer[16] == 0xa5);
    setup(8192, 8192); reply();
    assert(state.result == 0 && state.read_buffer[8191] == 0x5a);
    setup(16, 17); reply(); assert(state.result == -EMSGSIZE); no_copy();
    setup(16, 15); reply(); assert(state.result == -EMSGSIZE); no_copy();
    setup(16, UINT32_MAX); reply(); assert(state.result == -EMSGSIZE); no_copy();
    setup(8193, 8193); reply(); assert(state.result == -EMSGSIZE); no_copy();
    setup(0, 0); reply(); assert(state.result == -EMSGSIZE); no_copy();
    setup(16, 16); mapped = false; reply(); assert(state.result == -EFAULT); no_copy();
    setup(16, 8193); state.pending = false; reply();
    assert(state.reply.done == 0); no_copy();
    setup(16, 8193); state.poisoned = true; reply();
    assert(state.reply.done == 0); no_copy();
    setup(16, 16); packet.msg.erap.param.raw.params[0] = TFA_RES_WRITE; reply();
    assert(state.result == -EPROTO && state.poisoned); no_copy();
    setup(16, 16); packet.msg.erap.param.raw.params[0] = TFA_INVALID_PARAM; reply();
    assert(state.result == -EREMOTEIO); no_copy();
    setup(16, 16); state.expected_reply = TFA_RES_WRITE;
    packet.msg.erap.param.raw.params[0] = TFA_RES_WRITE; reply();
    assert(state.result == 0); no_copy();
    setup(16, 16); packet.msg.erap.msgtype = 0;
    assert(abox_tfa_reply(IPC_ERAP, &state, &packet) == IRQ_NONE);
    assert(state.pending && state.reply.done == 0); no_copy();
    setup(16, 16); reply(); memset(state.read_buffer, 0xa5, sizeof(state.read_buffer));
    reply(); assert(state.reply.done == 1); no_copy();
    puts("15 production-handler cases passed");
    return 0;
}
'''
    program = prefix + constants + "\n" + context + "\n" + bodies + "\n" + tests
    with tempfile.TemporaryDirectory(prefix="a50-tfa-ipc-") as folder:
        folder = Path(folder)
        cfile, binary = folder / "check.c", folder / "check"
        cfile.write_text(program)
        command = ["cc", "-std=gnu11", "-Wall", "-Wextra", "-Werror",
                   "-fsanitize=address,undefined", "-fno-sanitize-recover=all", str(cfile), "-o", str(binary)]
        subprocess.run(command, check=True)
        subprocess.run([str(binary)], check=True)
        # Prove a missing response-length check is caught; no kernel files changed.
        mutant = program.replace("bytes != sync->expected_bytes", "false")
        assert mutant != program
        cfile.write_text(mutant)
        subprocess.run(command, check=True)
        result = subprocess.run([str(binary)], capture_output=True)
        assert result.returncode != 0, "missing length check escaped the tests"
        assert b"state.result == -EMSGSIZE" in result.stderr, result.stderr.decode(errors="replace")
        print("Removed response-length check is rejected")


if __name__ == "__main__":
    main()

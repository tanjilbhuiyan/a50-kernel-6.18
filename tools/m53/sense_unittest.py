#!/usr/bin/env python3
"""Exercise the real UFS guard rejection and SCSI sense dispatch on the host.

Usage: python3 -I tools/m53/sense_unittest.py KERNEL_TREE
Compiles extracted kernel C, with transport/logging mocked. Verifies policy
denials preserve WRITE(10), then reproduces test 2 with the original response.
Boundary/mutation coverage remains in tools/m52/guard_unittest.py.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

tree = Path(sys.argv[1])
ufs = (tree / 'drivers/ufs/core/ufshcd.c').read_text()
scsi = (tree / 'drivers/scsi/scsi_lib.c').read_text()
sd = (tree / 'drivers/scsi/sd.c').read_text()
proto = (tree / 'include/scsi/scsi_proto.h').read_text()
query = (tree / 'include/ufs/ufs.h').read_text()

decisions = ufs[ufs.index('/* A50-GUARD-BEGIN'):ufs.index('/* A50-GUARD-END */')]
queue = ufs[ufs.index('static int ufshcd_queuecommand('):]
denial = queue[queue.index('#ifdef CONFIG_A50_UFS_SAFE'):
               queue.index('#endif') + len('#endif')]

# Keep the entire kernel sense switch, including both the fallback and
# DATA_PROTECT cases. Count braces after removing comments, so comments
# cannot change where the extracted switch ends.
dispatch = scsi[scsi.index('switch (sshdr.sense_key) {'):]
dispatch = re.sub(r'/\*.*?\*/', '', dispatch, flags=re.S)
depth = 0
for i, char in enumerate(dispatch):
    depth += (char == '{') - (char == '}')
    if char == '}' and depth == 0:
        dispatch = dispatch[:i + 1]
        break
else:
    raise RuntimeError('unterminated sense switch')

# Real sd_done ILLEGAL_REQUEST handling, including discard/WRITE SAME disable.
sd_done = sd[sd.index('static int sd_done('):]
sd_case = sd_done[sd_done.index('\tcase ILLEGAL_REQUEST:'):
                  sd_done.index('\n\tdefault:', sd_done.index('\tcase ILLEGAL_REQUEST:'))]

names = '''TEST_UNIT_READY REQUEST_SENSE READ_6 INQUIRY MODE_SENSE START_STOP
READ_CAPACITY READ_10 MODE_SENSE_10 READ_16 REPORT_LUNS SERVICE_ACTION_IN_16
SAI_READ_CAPACITY_16 WRITE_6 WRITE_10 WRITE_16 SYNCHRONIZE_CACHE
SYNCHRONIZE_CACHE_16 UNMAP WRITE_SAME WRITE_SAME_16 WRITE_BUFFER FORMAT_UNIT
UNIT_ATTENTION ILLEGAL_REQUEST ABORTED_COMMAND NOT_READY VOLUME_OVERFLOW
DATA_PROTECT COMPLETED'''.split()
defs = []
for name in names:
    value = re.search(r'#define\s+' + name + r'\s+(0x[\da-fA-F]+)', proto)
    if value is None:
        raise RuntimeError('missing SCSI constant: ' + name)
    defs.append(f'#define {name} {value[1]}')
enum = query[query.index('enum query_opcode {'):].split('};', 1)[0]
defs += [f'#define {k} {v}' for k, v in re.findall(
    r'(UPIU_QUERY_OPCODE_\w+)\s*=\s*(0x[\da-fA-F]+)', enum)]
defs.append('#define QUERY_FLAG_IDN_FDEVICEINIT ' + re.search(
    r'QUERY_FLAG_IDN_FDEVICEINIT\s*=\s*(0x[\da-fA-F]+)', query)[1])

head = r'''
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
#define noinline
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define CONFIG_A50_UFS_SAFE 1
#define A50_UD_FIRST 0x1c8700ULL
#define A50_UD_LAST 0xee42ffULL
#define dev_warn_ratelimited(...) do {} while (0)
#define fallthrough __attribute__((fallthrough))
enum {ACTION_FAIL, ACTION_REPREP, ACTION_DELAYED_REPREP,
      ACTION_RETRY, ACTION_DELAYED_RETRY};
enum {BLK_STS_PROTECTION, BLK_STS_TARGET, BLK_STS_ZONE_OPEN_RESOURCE};
struct device {u64 lun; int use_10_for_rw, removable, changed;};
struct scsi_sense_hdr {int sense_key, asc, ascq;};
struct scsi_cmnd {u8 cmnd[16]; struct device *device;
                 struct scsi_sense_hdr sense; int completed;};
static void scsi_build_sense(struct scsi_cmnd *cmd, int descriptor,
                             int key, int asc, int ascq) {
    cmd->sense = (struct scsi_sense_hdr){key, asc, ascq};
}
static void scsi_done(struct scsi_cmnd *cmd) {cmd->completed++;}
struct scsi_disk {int discard_enabled, write_same_enabled;};
struct request {unsigned rq_flags;};
#define RQF_QUIET 1
static int sd_completed_bytes(struct scsi_cmnd *cmd) {return 0;}
static void sd_disable_discard(struct scsi_disk *disk) {disk->discard_enabled = 0;}
static void sd_disable_write_same(struct scsi_disk *disk) {disk->write_same_enabled = 0;}
'''
wrapper = '''
static int guard(struct scsi_cmnd *cmd) {
%s
return 1;
}
static int completion(struct scsi_cmnd *cmd) {
struct scsi_sense_hdr sshdr = cmd->sense;
int action = -1, blk_stat = -1;
%s
return action;
}
static int sd_features_after(struct scsi_cmnd *cmd) {
struct scsi_cmnd *SCpnt = cmd;
struct scsi_sense_hdr sshdr = cmd->sense;
struct scsi_disk disk = {1, 1}, *sdkp = &disk;
struct request request = {0}, *req = &request;
int good_bytes = 0;
switch (sshdr.sense_key) {
%s
default: break;
}
return disk.discard_enabled | (disk.write_same_enabled << 1);
}
''' % (denial, dispatch, sd_case)
main = r'''
static int failures;
#define CHECK(x) do {if (!(x)) {puts("FAIL: " #x); failures++;}} while (0)
static void write10(struct scsi_cmnd *cmd, u32 lba, unsigned len) {
    memset(cmd->cmnd, 0, sizeof(cmd->cmnd));
    cmd->completed = 0;
    cmd->cmnd[0] = WRITE_10;
    cmd->cmnd[1] = 8; /* FUA must stay usable after denied EFS write. */
    cmd->cmnd[2] = lba >> 24; cmd->cmnd[3] = lba >> 16;
    cmd->cmnd[4] = lba >> 8; cmd->cmnd[5] = lba;
    cmd->cmnd[7] = len >> 8; cmd->cmnd[8] = len;
}
int main(void) {
    struct device disk = {.lun = 0, .use_10_for_rw = 1};
    struct scsi_cmnd cmd = {.device = &disk};
    /* Actual test-2 sequence: denied EFS, then legal userdata on same LUN. */
    write10(&cmd, 0x1000, 1);
    CHECK(guard(&cmd) == 0);
    CHECK(cmd.completed == 1);
    CHECK(cmd.sense.sense_key == DATA_PROTECT);
    CHECK(cmd.sense.asc == 0x27 && cmd.sense.ascq == 0);
    CHECK(completion(&cmd) == ACTION_FAIL);
    CHECK(disk.use_10_for_rw == 1);
    write10(&cmd, 0x1c9572, 1);
    CHECK(guard(&cmd) == 1);
    CHECK(cmd.completed == 0);
    CHECK(cmd.cmnd[0] == WRITE_10 && cmd.cmnd[1] == 8);
    /* Denials at end boundary and on another LUN retain protection too. */
    write10(&cmd, 0xee42ff, 2);
    CHECK(guard(&cmd) == 0 && completion(&cmd) == ACTION_FAIL);
    CHECK(disk.use_10_for_rw == 1);
    write10(&cmd, 0x1c9572, 1); disk.lun = 1;
    CHECK(guard(&cmd) == 0 && completion(&cmd) == ACTION_FAIL);
    disk.lun = 0;
    memset(cmd.cmnd, 0, sizeof(cmd.cmnd));
    cmd.cmnd[0] = WRITE_16; /* Denied address zero on the protected disk. */
    cmd.cmnd[13] = 1;
    CHECK(guard(&cmd) == 0 && completion(&cmd) == ACTION_FAIL);
    CHECK(cmd.sense.sense_key == DATA_PROTECT && cmd.sense.asc == 0x27);
    CHECK(disk.use_10_for_rw == 1);
    cmd.cmnd[0] = WRITE_6;
    CHECK(guard(&cmd) == 0 && completion(&cmd) == ACTION_FAIL);
    cmd.cmnd[0] = UNMAP;
    CHECK(guard(&cmd) == 0 && completion(&cmd) == ACTION_FAIL);
    CHECK(cmd.sense.sense_key == ILLEGAL_REQUEST && cmd.sense.asc == 0x20);
    CHECK(sd_features_after(&cmd) == 2); /* sd disables discard. */
    for (int i = 0; i < 2; i++) {
        cmd.cmnd[0] = i ? WRITE_SAME_16 : WRITE_SAME;
        cmd.cmnd[1] = 8;
        CHECK(guard(&cmd) == 0 && completion(&cmd) == ACTION_FAIL);
        CHECK(sd_features_after(&cmd) == 2);
        cmd.cmnd[1] = 0;
        CHECK(guard(&cmd) == 0 && completion(&cmd) == ACTION_FAIL);
        CHECK(sd_features_after(&cmd) == 1); /* sd disables WRITE SAME. */
    }
    CHECK(disk.use_10_for_rw == 1);
    /* Positive control: actual SCSI switch must reproduce the old bug. */
    write10(&cmd, 0x1000, 1);
    scsi_build_sense(&cmd, 0, ILLEGAL_REQUEST, 0x20, 0);
    CHECK(completion(&cmd) == ACTION_REPREP);
    CHECK(disk.use_10_for_rw == 0);
    return failures ? 1 : 0;
}
'''


def run(rejection):
    with tempfile.TemporaryDirectory(prefix='a50-sense-') as tmp:
        src, binary = Path(tmp) / 'test.c', Path(tmp) / 'test'
        src.write_text(head + '\n'.join(defs) + '\n' + decisions +
                       wrapper.replace(denial, rejection) + main)
        subprocess.run(['gcc', '-std=gnu11', '-Wall', '-Wextra',
                        '-Wno-unused-parameter', '-Wno-unused-function',
                        '-Wno-sign-compare',
                        '-Wno-unused-but-set-variable', '-o', str(binary), str(src)], check=True)
        return subprocess.run([str(binary)], capture_output=True, text=True)


fixed = run(denial)
print('Guard + real SCSI sense switch:', 'PASS' if fixed.returncode == 0 else 'FAIL')
print(fixed.stdout, end='')
original = denial.replace('DATA_PROTECT, 0x27, 0', 'ILLEGAL_REQUEST, 0x20, 0')
assert original != denial, 'fixed sense response not found'
regression = run(original)
assert regression.returncode != 0, 'original bug was not detected'
assert 'FAIL: disk.use_10_for_rw == 1' in regression.stdout
print('Original unsupported-opcode response: regression caught')
broad = denial.replace('ILLEGAL_REQUEST, 0x20, 0', 'DATA_PROTECT, 0x27, 0')
assert broad != denial, 'unsupported-operation response not found'
regression = run(broad)
assert regression.returncode != 0 and 'FAIL: sd_features_after(&cmd) == 2' in regression.stdout
print('Broad DATA_PROTECT response: repeated-discard regression caught')
sys.exit(fixed.returncode)

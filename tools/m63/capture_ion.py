#!/usr/bin/env python3
"""Capture AArch64 allocator ION ioctl argument buffers on the baseline.

Run as root on the phone: python3 capture_ion.py ALLOCATOR_PID [SECONDS].
Reads the ioctl structures only. Traced threads resume between syscall stops
and detach on completion. Entry/exit comes from x7 in the baseline's
arch/arm64/kernel/ptrace.c, tracehook_report_syscall().
"""
import ctypes
import errno
import json
import os
import signal
import struct
import sys
import time


PTRACE_SYSCALL = 24
PTRACE_DETACH = 17
PTRACE_GETREGSET = 0x4204
PTRACE_SEIZE = 0x4206
PTRACE_INTERRUPT = 0x4207
PTRACE_O_TRACESYSGOOD = 1
NT_PRSTATUS = 1
WAIT_ALL = 0x40000000
ION_ALLOC = 0xC0184900
ION_QUERY = 0xC0184908


class IOVec(ctypes.Structure):
    _fields_ = [('base', ctypes.c_void_p), ('length', ctypes.c_size_t)]


libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.restype = ctypes.c_long
libc.ptrace.argtypes = [ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p, ctypes.c_void_p]


def ptrace(request, tid, address=0, data=0):
    result = libc.ptrace(request, tid, address, data)
    if result == -1:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))
    return result


def emit(record):
    print(json.dumps(record), flush=True)


def registers(tid):
    values = (ctypes.c_ulonglong * 34)()
    vector = IOVec(ctypes.addressof(values), ctypes.sizeof(values))
    ptrace(PTRACE_GETREGSET, tid, NT_PRSTATUS, ctypes.byref(vector))
    if vector.length != ctypes.sizeof(values):
        raise RuntimeError('Expected native AArch64 registers')
    return values


def decode(command, data):
    if command == ION_ALLOC:
        length, mask, flags, fd, unused = struct.unpack('<QIIII', data)
        return dict(length=length, heap_mask=mask, flags=flags, fd=fd, unused=unused)
    count, reserved0, address, reserved1, reserved2 = struct.unpack('<IIQII', data)
    return dict(count=count, heaps_pointer=address, reserved=[reserved0, reserved1, reserved2])


def capture(pid, duration):
    attached = set()
    stopped = set()
    pending = {}
    memory = None
    captured = 0
    try:
        for entry in sorted(os.listdir(f'/proc/{pid}/task'), key=int):
            tid = int(entry)
            try:
                ptrace(PTRACE_SEIZE, tid, 0, PTRACE_O_TRACESYSGOOD)
            except OSError as error:
                if error.errno == errno.ESRCH:
                    continue
                raise
            attached.add(tid)
            ptrace(PTRACE_INTERRUPT, tid)
        memory = os.open(f'/proc/{pid}/mem', os.O_RDONLY | os.O_CLOEXEC)
        emit(dict(event='started', pid=pid, threads=len(attached), seconds=duration))
        deadline = time.monotonic() + duration
        while attached and time.monotonic() < deadline:
            tid, status = os.waitpid(-1, os.WNOHANG | WAIT_ALL)
            if tid == 0:
                time.sleep(0.002)
                continue
            if os.WIFEXITED(status) or os.WIFSIGNALED(status):
                attached.discard(tid)
                pending.pop(tid, None)
                continue
            if not os.WIFSTOPPED(status):
                continue
            stopped.add(tid)
            stop_signal = os.WSTOPSIG(status)
            delivery = 0
            if stop_signal == signal.SIGTRAP | 0x80:
                regs = registers(tid)
                if regs[7] == 0:
                    pending.pop(tid, None)
                    if regs[8] == 29 and regs[1] in (ION_ALLOC, ION_QUERY):
                        target = os.readlink(f'/proc/{pid}/fd/{regs[0]}')
                        if target == '/dev/ion':
                            command = regs[1]
                            data = os.pread(memory, 24, regs[2])
                            pending[tid] = dict(command=command, address=regs[2], input=decode(command, data))
                elif regs[7] == 1 and tid in pending:
                    record = pending.pop(tid)
                    command = record['command']
                    result = ctypes.c_longlong(regs[0]).value
                    output = decode(command, os.pread(memory, 24, record['address']))
                    item = dict(event='ioctl', tid=tid, command=hex(command), result=result,
                                input=record['input'], output=output)
                    if command == ION_QUERY:
                        address = output.pop('heaps_pointer')
                        record['input'].pop('heaps_pointer')
                        if result == 0 and address and 0 < output['count'] <= 32:
                            blob = os.pread(memory, 52 * output['count'], address)
                            item['heaps'] = []
                            for offset in range(0, len(blob), 52):
                                name, kind, heap_id, size, flags, reserved = struct.unpack_from('<32sIIIII', blob, offset)
                                item['heaps'].append(dict(name=name.split(b'\0')[0].decode(), type=kind,
                                                          id=heap_id, size=size, heap_flags=flags,
                                                          reserved2=reserved))
                    emit(item)
                    captured += 1
            elif status >> 16 != 128:
                delivery = stop_signal
            ptrace(PTRACE_SYSCALL, tid, 0, delivery)
            stopped.discard(tid)
    finally:
        # Interrupt running tracees before detaching. No EXITKILL option is used.
        for tid in attached - stopped:
            try:
                ptrace(PTRACE_INTERRUPT, tid)
            except OSError as error:
                if error.errno == errno.ESRCH:
                    attached.discard(tid)
        deadline = time.monotonic() + 5
        while attached and time.monotonic() < deadline:
            for tid in list(stopped):
                try:
                    ptrace(PTRACE_DETACH, tid)
                except OSError as error:
                    if error.errno != errno.ESRCH:
                        raise
                attached.discard(tid)
                stopped.discard(tid)
            if not attached:
                break
            tid, status = os.waitpid(-1, os.WNOHANG | WAIT_ALL)
            if tid:
                if os.WIFSTOPPED(status):
                    stopped.add(tid)
                elif os.WIFEXITED(status) or os.WIFSIGNALED(status):
                    attached.discard(tid)
            else:
                time.sleep(0.01)
        if memory is not None:
            os.close(memory)
        emit(dict(event='finished', captured=captured, remaining_tracees=len(attached)))


def interrupted(signum, frame):
    raise KeyboardInterrupt


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupted)
    capture(int(sys.argv[1]), float(sys.argv[2]) if len(sys.argv) > 2 else 45)

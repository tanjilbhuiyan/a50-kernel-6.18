#!/usr/bin/env python3
"""Inspect a native AArch64 handler; optionally run one bounded diagnostic copy."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import resource
import signal
import socket
import struct
import subprocess
import time

HANDLER = '/usr/bin/lomiri-telephony-service-handler'
BUS_NAMES = ('com.lomiri.TelephonyServiceHandler', 'org.freedesktop.Telepathy.Client.TelephonyServiceHandler')
ENV_NAMES = {'HOME', 'USER', 'LOGNAME', 'PATH', 'DISPLAY', 'WAYLAND_DISPLAY', 'MIR_SOCKET',
             'XDG_RUNTIME_DIR', 'XDG_SESSION_TYPE', 'DBUS_SESSION_BUS_ADDRESS', 'PULSE_SERVER',
             'PULSE_RUNTIME_PATH', 'QT_QPA_PLATFORM', 'QT_PLUGIN_PATH', 'QML2_IMPORT_PATH',
             'LD_LIBRARY_PATH', 'LD_PRELOAD', 'GLIBC_TUNABLES', 'LANG', 'LC_ALL',
             'DBUS_STARTER_ADDRESS', 'DBUS_STARTER_BUS_TYPE', 'XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS',
             'XDG_DATA_HOME', 'XDG_DATA_DIRS', 'XDG_CACHE_HOME', 'DESKTOP_SESSION', 'EGL_PLATFORM'}


def environment(raw):
    return dict(item.decode(errors='surrogateescape').split('=', 1)
                for item in raw.split(b'\0') if b'=' in item)


def visible_environment(env):
    return {name: value for name, value in env.items()
            if name in ENV_NAMES or name.startswith(('QT_', 'MIR_', 'WAYLAND_'))}


def pollfds(data, count):
    if not 1 <= count <= 64 or len(data) != count * 8:
        raise ValueError('invalid pollfd count or length')
    return [{'fd': fd, 'events': hex(events & 0xffff), 'revents': hex(revents & 0xffff)}
            for fd, events, revents in struct.iter_unpack('<ihh', data)]


def unix_rows(text):
    rows = {}
    for line in text.splitlines()[1:]:
        fields = line.split(maxsplit=7)
        if len(fields) >= 7:
            rows[fields[6]] = {'type': fields[4], 'state': fields[5],
                               'bound_path': fields[7] if len(fields) == 8 else None}
    return rows


def socket_details(fd):
    # Duplicate only for read-only socket queries; never receive/send data.
    duplicate = os.dup(fd)
    try:
        sock = socket.socket(fileno=duplicate)
    except BaseException:
        os.close(duplicate)
        raise
    with sock:
        convert = lambda value: value.decode(errors='backslashreplace') if isinstance(value, bytes) else value
        result = {'local_address': convert(sock.getsockname())}
        try:
            result['peer_address'] = convert(sock.getpeername())
            pid, uid, gid = struct.unpack('=3i', sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            result['peer_credentials'] = {'pid': pid, 'uid': uid, 'gid': gid}
            try:
                result['peer_exe'] = os.readlink('/proc/' + str(pid) + '/exe')
            except OSError:
                pass
        except OSError as error:
            result['peer_unverified'] = str(error)
        return result


def peer_info(pidfd, fd, inode):
    # Native AArch64 asm-generic unistd.h defines pidfd_getfd as syscall 438.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    duplicate = libc.syscall(ctypes.c_long(438), ctypes.c_int(pidfd), ctypes.c_int(fd), ctypes.c_uint(0))
    if duplicate < 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    try:
        if os.fstat(duplicate).st_ino != inode:
            raise ValueError('fd identity changed before duplication')
        return socket_details(duplicate)
    finally:
        os.close(duplicate)


def inspect(pid):
    proc = Path('/proc') / str(pid)
    if os.readlink(proc / 'exe') != HANDLER:
        raise ValueError('PID is not the expected handler executable')
    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines() if ':' in line)
    uid, gid = int(status['Uid'].split()[0]), int(status['Gid'].split()[0])
    if uid != 32011:
        raise ValueError('handler is not running as phablet')
    env = environment((proc / 'environ').read_bytes())
    sockets = unix_rows((proc / 'net/unix').read_text())
    fds = {}
    try:
        pidfd = os.pidfd_open(pid, 0)
    except (AttributeError, OSError):
        pidfd = None
    for fd in sorted((proc / 'fd').iterdir(), key=lambda p: int(p.name)):
        try:
            target = os.readlink(fd)
            entry = {'target': target, 'fdinfo': (proc / 'fdinfo' / fd.name).read_text().strip()}
            if target.startswith('socket:['):
                entry['unix'] = sockets.get(target[8:-1])
                try:
                    if pidfd is None:
                        raise ValueError('pidfd_open unavailable')
                    entry['peer'] = peer_info(pidfd, int(fd.name), int(target[8:-1]))
                except (OSError, ValueError) as error:
                    entry['peer'] = {'unverified': str(error)}
            fds[fd.name] = entry
        except OSError as error:
            fds[fd.name] = {'error': str(error)}
    if pidfd is not None:
        os.close(pidfd)
    result = {'pid': pid, 'exe': HANDLER, 'uid': uid, 'gid': gid,
              'threads': int(status['Threads']), 'environment': visible_environment(env),
              'fds': fds, 'socket_note': 'bound_path belongs to this inode; an unnamed client does not identify its peer',
              'maps': (proc / 'maps').read_text().splitlines(), 'poll': {}}
    try:
        header = Path(HANDLER).read_bytes()[:20]
        assert header[:5] == b'\x7fELF\x02' and struct.unpack_from('<H', header, 18)[0] == 183
        before = (proc / 'syscall').read_text().split()
        assert int(before[0]) == 73, 'main thread is not in native AArch64 ppoll'
        pointer, count = int(before[1], 0), int(before[2], 0)
        assert pointer > 0 and 1 <= count <= 64
        with (proc / 'mem').open('rb', buffering=0) as memory:
            memory.seek(pointer)
            decoded = pollfds(memory.read(count * 8), count)
        after = (proc / 'syscall').read_text().split()
        assert before[:3] == after[:3], 'syscall changed while reading pollfd array'
        for row in decoded:
            row['descriptor'] = fds.get(str(row['fd']))
        result['poll'] = {'syscall': before, 'fds': decoded}
    except (OSError, ValueError, AssertionError) as error:
        result['poll'] = {'unverified': str(error)}
    return result, env, uid, gid, [int(x) for x in status['Groups'].split()]


def credentials(uid, gid, groups):
    return {'user': uid, 'group': gid, 'extra_groups': groups} if os.geteuid() == 0 or uid != os.getuid() else {}


def bounded_child(argv, env, uid, gid, groups, output, seconds):
    """Signal only this newly created process group, never the inspected PID."""
    with output.open('wb') as log:
        child = subprocess.Popen(argv, env=env, cwd=env.get('HOME', '/'),
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                 **credentials(uid, gid, groups), start_new_session=True)
        timed_out = False
        try:
            child.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            # Also clean up descendants if the main child exits first.
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                pass
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait(timeout=3)
    return {'pid': child.pid, 'returncode': child.returncode, 'timeout': timed_out,
            'seconds_limit': seconds, 'log_bytes': output.stat().st_size}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pid', type=int)
    parser.add_argument('--manual', action='store_true')
    args = parser.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_FSIZE, (4 * 1024 * 1024, 4 * 1024 * 1024))
    result, env, uid, gid, groups = inspect(args.pid)
    print(json.dumps(result, indent=2), flush=True)
    if not args.manual:
        return
    if result['threads'] != 1:
        print('MANUAL_SKIPPED: original handler is no longer the one-thread startup case')
        return
    # A separate handler must never displace an already working bus owner.
    for name in BUS_NAMES:
        check = subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
                                '--object-path', '/org/freedesktop/DBus',
                                '--method', 'org.freedesktop.DBus.GetNameOwner', name],
                               env=env, **credentials(uid, gid, groups),
                               capture_output=True, text=True, timeout=5)
        print('MANUAL_BUS_OWNER_CHECK', name, check.returncode, check.stdout.strip(), check.stderr.strip(), flush=True)
        if check.returncode == 0 or not any(marker in check.stderr for marker in ('NameHasNoOwner', 'has no owner')):
            print('MANUAL_SKIPPED: bus owner exists or absence could not be verified')
            return
    if not Path('/proc', str(args.pid)).exists():
        print('MANUAL_SKIPPED: original exited before diagnostic launch')
        return
    env.pop('NOTIFY_SOCKET', None)
    env.update(QT_DEBUG_PLUGINS='1', QT_LOGGING_RULES='qt.qpa.*=true;qt.wayland.*=true;qtmir.*=true',
               WAYLAND_DEBUG='client', MIR_CLIENT_LOG_LEVEL='debug')
    output = Path('/run/a50-m75-i3/manual-handler.log')
    print('MANUAL_BEGIN', json.dumps({'uptime': Path('/proc/uptime').read_text().split()[0],
          'original_pid': args.pid, 'debug_environment': visible_environment(env),
          'note': 'same display selection and session bus; a debug child is not normal-service readiness'}), flush=True)
    started = time.monotonic()
    child_result = bounded_child([HANDLER], env, uid, gid, groups, output, 25)
    child_result['elapsed'] = round(time.monotonic() - started, 3)
    print('MANUAL_RESULT', json.dumps(child_result), flush=True)
    # The tmpfs holds the complete log; bound collector output independently.
    print('MANUAL_LOG_BEGIN', flush=True)
    print(output.read_bytes()[-1024 * 1024:].decode(errors='replace'), flush=True)
    print('MANUAL_LOG_END', flush=True)


if __name__ == '__main__':
    main()

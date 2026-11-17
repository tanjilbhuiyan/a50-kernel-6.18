#!/usr/bin/env python3
"""Query Samsung's EXYNOS_DISP_INFO metadata, followed by fbdev dimensions.

The stock handler copies panel metadata and preserves the caller's version
and reserved bytes. It changes no mode or framebuffer contents. Run on the
baseline or a diagnostic kernel; unsupported ioctl is recorded, not hidden.
"""
import array
import fcntl
import json
import os
import platform
import struct

SIZE = 248
EXYNOS_DISP_INFO = 0x40F84704  # _IOW('F', 260, struct decon_disp_info)
fd = os.open('/dev/fb0', os.O_RDONLY | os.O_CLOEXEC)
result = {'kernel': platform.release(), 'ioctl': hex(EXYNOS_DISP_INFO), 'size': SIZE}
try:
    data = array.array('B', bytes(SIZE))
    struct.pack_into('<I', data, 0, 2)  # HWC_2_0, as the stock 64-bit HAL sends.
    try:
        fcntl.ioctl(fd, EXYNOS_DISP_INFO, data, True)
    except OSError as exc:
        result['display_info'] = {'errno': exc.errno, 'error': exc.strerror}
    else:
        words = struct.unpack('<62I', data)
        result['display_info'] = {
            'version': words[0], 'psr_mode': words[1],
            'mres_enabled': words[2], 'mres_count': words[3],
            'resolutions': [dict(zip(
                ('width', 'height', 'dsc_enabled', 'dsc_width', 'dsc_height'),
                words[4 + i * 5:9 + i * 5])) for i in range(5)],
            'chip_version': words[29],
            'reserved_bytes_zero': not any(data[120:248]),
            'raw_hex': data.tobytes().hex(),
        }
    var = array.array('B', bytes(160))
    fcntl.ioctl(fd, 0x4600, var, True)
    words = struct.unpack('<40I', var)
    result['fbdev'] = {'xres': words[0], 'yres': words[1],
                       'width_mm': words[23], 'height_mm': words[22],
                       'reserved': list(words[36:40])}
    result['optional_mode_queries'] = {}
    for name, command, size in (
        ('mode_count', 0x400446BC, 4),
        ('mode_index_0', 0x401C46BD, 28),
        ('current_mode', 0x400446C1, 4),
    ):
        query = array.array('B', bytes(size))
        try:
            fcntl.ioctl(fd, command, query, True)
        except OSError as exc:
            reply = {'errno': exc.errno, 'error': exc.strerror}
        else:
            reply = {'words': list(struct.unpack('<' + 'I' * (size // 4), query))}
        result['optional_mode_queries'][name] = {'ioctl': hex(command), **reply}
finally:
    os.close(fd)
print(json.dumps(result, indent=2))

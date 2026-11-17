#!/usr/bin/env python3
"""Read the actual fbdev variable-screen ABI without changing display state."""
import array
import fcntl
import json
import os
import struct

fd = os.open('/dev/fb0', os.O_RDONLY | os.O_CLOEXEC)
try:
    data = array.array('B', bytes(160))
    fcntl.ioctl(fd, 0x4600, data, True)  # FBIOGET_VSCREENINFO
    values = struct.unpack('<40I', data)
    names = {
        0: 'xres', 1: 'yres', 2: 'xres_virtual', 3: 'yres_virtual',
        4: 'xoffset', 5: 'yoffset', 6: 'bits_per_pixel',
        22: 'height_mm', 23: 'width_mm', 25: 'pixclock_ps',
        26: 'left_margin', 27: 'right_margin', 28: 'upper_margin',
        29: 'lower_margin', 30: 'hsync_len', 31: 'vsync_len',
        32: 'sync', 33: 'vmode',
    }
    print(json.dumps({name: values[index] for index, name in names.items()}, indent=2))
finally:
    os.close(fd)

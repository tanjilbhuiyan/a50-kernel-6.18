/* SPDX-License-Identifier: GPL-2.0 */
/* G1: stock kbase ABI, metadata only; job submission is disabled in this context. */
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include "mali_kbase_ioctl.h"

_Static_assert(sizeof(struct kbase_ioctl_version_check) == 4, "version ABI");
_Static_assert(sizeof(struct kbase_ioctl_get_gpuprops) == 16, "properties ABI");
_Static_assert(KBASE_IOCTL_VERSION_CHECK == 0xc0048000UL, "version ioctl");
_Static_assert(KBASE_IOCTL_GET_GPUPROPS == 0x40108003UL, "properties ioctl");

static void fail(const char *what)
{
    fprintf(stderr, "FAIL: %s: %s\n", what, strerror(errno));
    exit(1);
}

static void require(int condition, const char *what)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        exit(1);
    }
}

static void expect_errno(int fd, struct kbase_ioctl_get_gpuprops *props, int error)
{
    errno = 0;
    require(ioctl(fd, KBASE_IOCTL_GET_GPUPROPS, props) == -1 && errno == error,
            "GET_GPUPROPS error handling");
}

int main(int argc, char **argv)
{
    int fd = open(argc > 1 ? argv[1] : "/dev/mali0", O_RDWR | O_CLOEXEC);
    if (fd < 0) fail("open mali");
    struct kbase_ioctl_version_check version = {0};
    if (ioctl(fd, KBASE_IOCTL_VERSION_CHECK, &version)) fail("VERSION_CHECK");
    printf("ABI %zu-bit VERSION_CHECK %u.%u\n", sizeof(void *) * 8,
            version.major, version.minor);
    require(version.major == BASE_UK_VERSION_MAJOR &&
            version.minor == BASE_UK_VERSION_MINOR, "r26p0 ABI version");
    /* BASE_CONTEXT_SYSTEM_MONITOR_SUBMIT_DISABLED (mali_base_jm_kernel.h). */
    struct kbase_ioctl_set_flags flags = {.create_flags = 1U << 1};
    if (ioctl(fd, KBASE_IOCTL_SET_FLAGS, &flags)) fail("SET_FLAGS (no jobs)");
    /* Verify this boot has the G1 gate; zero-sized requests cannot submit work. */
    union kbase_ioctl_mem_alloc allocation = {0};
    errno = 0;
    require(ioctl(fd, KBASE_IOCTL_MEM_ALLOC, &allocation) == -1 && errno == EOPNOTSUPP,
            "G1 diagnostic gate refuses allocations");
    struct kbase_ioctl_job_submit submit = {0};
    errno = 0;
    require(ioctl(fd, KBASE_IOCTL_JOB_SUBMIT, &submit) == -1 && errno == EOPNOTSUPP,
            "G1 diagnostic gate refuses jobs");
    struct kbase_ioctl_get_gpuprops props = {0};
    int size = ioctl(fd, KBASE_IOCTL_GET_GPUPROPS, &props);
    if (size < 0) fail("GET_GPUPROPS size");
    require(size > 0 && size < 65536, "bounded property buffer");
    unsigned char *buffer = calloc(1, (size_t)size);
    if (!buffer) fail("calloc");
    props.buffer = (uint64_t)(uintptr_t)buffer;
    props.size = (uint32_t)size;
    require(ioctl(fd, KBASE_IOCTL_GET_GPUPROPS, &props) == size,
            "GET_GPUPROPS full buffer");
    uint64_t values[256] = {0};
    unsigned char seen[256] = {0};
    size_t offset = 0;
    unsigned count = 0;
    while (offset < (size_t)size) {
        require((size_t)size - offset >= 4, "complete property key");
        uint32_t key = 0;
        for (unsigned i = 0; i < 4; i++) key |= (uint32_t)buffer[offset++] << (8 * i);
        unsigned width = 1U << (key & 3), id = key >> 2;
        require((size_t)size - offset >= width, "complete property value");
        uint64_t value = 0;
        for (unsigned i = 0; i < width; i++) value |= (uint64_t)buffer[offset++] << (8 * i);
        require(id < 256 && !seen[id], "unique property ID in range");
        seen[id] = 1;
        values[id] = value;
        count++;
        printf("property %u = 0x%" PRIx64 "\n", id, value);
    }
    const struct { unsigned id; uint64_t value; } expected[] = {
        {KBASE_GPUPROP_PRODUCT_ID, 0x6221},
        {KBASE_GPUPROP_MAJOR_REVISION, 0},
        {KBASE_GPUPROP_MINOR_REVISION, 1},
        {KBASE_GPUPROP_RAW_GPU_ID, 0x62210010},
        {KBASE_GPUPROP_RAW_SHADER_PRESENT, 7},
        {KBASE_GPUPROP_RAW_L2_PRESENT, 1},
        {KBASE_GPUPROP_RAW_AS_PRESENT, 0xff},
        {KBASE_GPUPROP_GPU_FREQ_KHZ_MAX, 260000},
    };
    for (unsigned i = 0; i < sizeof(expected) / sizeof(expected[0]); i++)
        require(seen[expected[i].id] && values[expected[i].id] == expected[i].value,
                "properties match G0b and fixed-clock platform");
    props.size--;
    expect_errno(fd, &props, EINVAL);
    props.size++;
    props.flags = 1;
    expect_errno(fd, &props, EINVAL);
    props.flags = 0;
    props.buffer = 1;
    expect_errno(fd, &props, EFAULT);
    free(buffer);
    if (close(fd)) fail("close");
    printf("RESULT: PASS (%u properties, no allocation or job submission)\n", count);
    return 0;
}

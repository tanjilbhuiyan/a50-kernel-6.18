#include <stdint.h>
#include <stddef.h>
#include <sys/ioctl.h>
typedef uint32_t u32; typedef uint8_t u8;
#define static_assert(x) _Static_assert((x), #x)
/* G2f metadata ABI: stock dpu20/decon.h and panels/decon_lcd.h. */
struct a50_lcd_res_info {
	u32 width, height, dsc_en, dsc_width, dsc_height;
};

struct a50_lcd_mres_info {
	u32 mres_en, mres_number;
	struct a50_lcd_res_info res_info[5];
};

struct a50_disp_info {
	u32 ver, psr_mode;
	struct a50_lcd_mres_info mres_info;
	u32 chip_ver;
	u8 reserved[128];
};

#define EXYNOS_DISP_INFO _IOW('F', 260, struct a50_disp_info)
static_assert(sizeof(struct a50_disp_info) == 248);
static_assert(offsetof(struct a50_disp_info, mres_info) == 8);
static_assert(offsetof(struct a50_disp_info, chip_ver) == 116);
static_assert(offsetof(struct a50_disp_info, reserved) == 120);
static_assert(EXYNOS_DISP_INFO == 0x40f84704);


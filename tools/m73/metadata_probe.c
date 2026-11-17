/* SPDX-License-Identifier: Apache-2.0 */
/* Native/compat check; metadata_abi.h is extracted from the driver as built. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include "metadata_abi.h"
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL line %d: %s errno=%d\n",__LINE__,#x,errno); exit(1); } } while(0)

int main(void)
{
 int fd = open("/dev/fb0",O_RDONLY|O_CLOEXEC);
 CHECK(fd>=0);
 struct a50_disp_info reply;
 memset(&reply,0xa5,sizeof(reply)); reply.ver=0x12345678;
 CHECK(ioctl(fd,EXYNOS_DISP_INFO,&reply)==0);
 CHECK(reply.ver==0x12345678 && reply.psr_mode==2 && reply.chip_ver==9610);
 struct a50_lcd_mres_info expected = {.mres_number=1,.res_info={{.width=68,.height=147}}};
 CHECK(memcmp(&reply.mres_info,&expected,sizeof(expected))==0);
 for(size_t i=0;i<sizeof(reply.reserved);i++) CHECK(reply.reserved[i]==0xa5);
 printf("PASS metadata ABI=%zu ioctl=0x%lx mode=%u chip=%u; caller fields preserved\n",sizeof(reply),(unsigned long)EXYNOS_DISP_INFO,reply.psr_mode,reply.chip_ver);
 errno=0; CHECK(ioctl(fd,EXYNOS_DISP_INFO,NULL)==-1 && errno==EFAULT);
 long size=sysconf(_SC_PAGESIZE); CHECK(size>0);
 void *p=mmap(NULL,size*2,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
 CHECK(p!=MAP_FAILED); CHECK(mprotect((char *)p+size,size,PROT_NONE)==0);
 errno=0; CHECK(ioctl(fd,EXYNOS_DISP_INFO,(char *)p+size-4)==-1 && errno==EFAULT);
 memset(p,0,sizeof(reply)); CHECK(mprotect(p,size,PROT_READ)==0);
 errno=0; CHECK(ioctl(fd,EXYNOS_DISP_INFO,p)==-1 && errno==EFAULT);
 CHECK(munmap(p,size*2)==0);
 uint32_t query=0; errno=0;
 CHECK(ioctl(fd,0x400446bc,&query)==-1 && errno==ENOTTY);
 CHECK(close(fd)==0);
 puts("RESULT: PASS (NULL/partial input, read-only output and optional-mode rejection)");
 return 0;
}

/* SPDX-License-Identifier: GPL-2.0-only */
/* Bounded stock-ABI checks; each case has its own non-submitting context. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <linux/dma-buf.h>
#include "memory_constants.h"
#include "mali_kbase_ioctl.h"
#include "ion.h"

_Static_assert(sizeof(union kbase_ioctl_mem_alloc)==32,"alloc ABI");
_Static_assert(sizeof(union kbase_ioctl_mem_query)==16,"query ABI");
_Static_assert(sizeof(union kbase_ioctl_mem_import)==24,"import ABI");
_Static_assert(sizeof(struct kbase_ioctl_mem_sync)==32,"sync ABI");
_Static_assert(KBASE_IOCTL_MEM_ALLOC==0xc0208005UL,"alloc ioctl");
_Static_assert(KBASE_IOCTL_MEM_QUERY==0xc0108006UL,"query ioctl");
_Static_assert(KBASE_IOCTL_MEM_IMPORT==0xc0188016UL,"import ioctl");
_Static_assert(KBASE_IOCTL_MEM_SYNC==0x4020800fUL,"sync ioctl");
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL line %d: %s errno=%d (%s)\n",__LINE__,#x,errno,strerror(errno)); exit(1); } } while(0)
#define ACCESS (BASE_MEM_PROT_CPU_RD|BASE_MEM_PROT_CPU_WR|BASE_MEM_PROT_GPU_RD|BASE_MEM_PROT_GPU_WR)
static size_t page;
struct context { int fd; void *tracking; };

static int descriptors(void)
{
 DIR *d=opendir("/proc/self/fd"); CHECK(d); int n=0;
 while(readdir(d)) n++;
 CHECK(closedir(d)==0); return n;
}

static void descriptor_check(int before,int allow_stock_tracker)
{
 int after=descriptors();
 if(after!=before) {
  unsigned trackers=0;char expected[64];snprintf(expected,sizeof(expected),"anon_inode:%ld",(long)getpid());
  DIR *d=opendir("/proc/self/fd");CHECK(d);struct dirent *entry;
  while((entry=readdir(d))) {
   if(entry->d_name[0]=='.') continue;
   char path[512],target[512];snprintf(path,sizeof(path),"/proc/self/fd/%s",entry->d_name);
   ssize_t n=readlink(path,target,sizeof(target)-1);
   if(n>=0) {
    target[n]=0;
    if(!strcmp(target,expected) && (fcntl(atoi(entry->d_name),F_GETFD)&FD_CLOEXEC)) trackers++;
   }
  }
  closedir(d);
  /* Samsung 4.14 dma-buf-trace.c creates one per-task fd on first export. */
  if(allow_stock_tracker && after==before+1 && trackers==1) {
   puts("PASS exact stock per-task dma-buf tracker identified (released at child exit)");return;
  }
  fprintf(stderr,"descriptor count before=%d after=%d recognized_trackers=%u\n",before,after,trackers);
 }
 CHECK(after==before);
}

static struct context context_open(int track)
{
 struct context c={.fd=open("/dev/mali0",O_RDWR|O_CLOEXEC),.tracking=MAP_FAILED}; CHECK(c.fd>=0);
 struct kbase_ioctl_version_check v={0}; CHECK(ioctl(c.fd,KBASE_IOCTL_VERSION_CHECK,&v)==0);
 CHECK(v.major==BASE_UK_VERSION_MAJOR && v.minor==BASE_UK_VERSION_MINOR);
 struct kbase_ioctl_set_flags f={.create_flags=BASE_CONTEXT_SYSTEM_MONITOR_SUBMIT_DISABLED};
 CHECK(ioctl(c.fd,KBASE_IOCTL_SET_FLAGS,&f)==0);
 if(track) {
  c.tracking=mmap(NULL,page,PROT_NONE,MAP_SHARED,c.fd,BASE_MEM_MAP_TRACKING_HANDLE);
  CHECK(c.tracking!=MAP_FAILED);
 }
 return c;
}

static void context_close(struct context c)
{
 if(c.tracking!=MAP_FAILED) CHECK(munmap(c.tracking,page)==0);
 CHECK(close(c.fd)==0);
}

static union kbase_ioctl_mem_alloc alloc(int fd,unsigned pages)
{
 union kbase_ioctl_mem_alloc a={.in={.va_pages=pages,.commit_pages=pages,
  .flags=ACCESS|BASE_MEM_CACHED_CPU|BASE_MEM_SAME_VA}};
 CHECK(ioctl(fd,KBASE_IOCTL_MEM_ALLOC,&a)==0);
 CHECK(a.out.gpu_va && (a.out.flags&BASE_MEM_SAME_VA)); return a;
}

static uint64_t query(int fd,uint64_t va,uint64_t type)
{
 union kbase_ioctl_mem_query q={.in={.gpu_addr=va,.query=type}};
 CHECK(ioctl(fd,KBASE_IOCTL_MEM_QUERY,&q)==0); return q.out.value;
}

static void expect_query_error(int fd,uint64_t va,uint64_t type)
{
 union kbase_ioctl_mem_query q={.in={.gpu_addr=va,.query=type}};
 errno=0; CHECK(ioctl(fd,KBASE_IOCTL_MEM_QUERY,&q)==-1 && errno==EINVAL);
}

static void sync_mem(int fd,uint64_t va,void *cpu,size_t size,unsigned type,int expected)
{
 struct kbase_ioctl_mem_sync s={.handle=va,.user_addr=(uintptr_t)cpu,.size=size,.type=type};
 errno=0; int rc=ioctl(fd,KBASE_IOCTL_MEM_SYNC,&s);
 if(expected) CHECK(rc==-1 && errno==expected); else CHECK(rc==0);
}

static void tracking_case(void)
{
 int before=descriptors(); struct context c=context_open(0);
 union kbase_ioctl_mem_alloc a={.in={.va_pages=1,.commit_pages=1,.flags=ACCESS|BASE_MEM_SAME_VA}};
 errno=0; CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_ALLOC,&a)==-1 && errno==EINVAL);
 c.tracking=mmap(NULL,page,PROT_NONE,MAP_SHARED,c.fd,BASE_MEM_MAP_TRACKING_HANDLE);CHECK(c.tracking!=MAP_FAILED);
 void *duplicate=mmap(NULL,page,PROT_NONE,MAP_SHARED,c.fd,BASE_MEM_MAP_TRACKING_HANDLE);
 CHECK(duplicate==MAP_FAILED);
 context_close(c);descriptor_check(before,0);
 puts("PASS tracking prerequisite, duplicate refusal, context/fd cleanup");
}

static void native_case(void)
{
 int before=descriptors();struct context c=context_open(1);
 const unsigned sizes[]={1,2,4,8,2,1,4,2};
 for(unsigned n=0;n<sizeof(sizes)/sizeof(sizes[0]);n++) {
  size_t len=sizes[n]*page;union kbase_ioctl_mem_alloc a=alloc(c.fd,sizes[n]);
  unsigned char *p=mmap(NULL,len,PROT_READ|PROT_WRITE,MAP_SHARED,c.fd,(off_t)a.out.gpu_va);CHECK(p!=MAP_FAILED);
  uint64_t va=(uintptr_t)p;
  CHECK(query(c.fd,va,KBASE_MEM_QUERY_VA_SIZE)==sizes[n]);
  CHECK(query(c.fd,va,KBASE_MEM_QUERY_COMMIT_SIZE)==sizes[n]);
  CHECK((query(c.fd,va,KBASE_MEM_QUERY_FLAGS)&(ACCESS|BASE_MEM_CACHED_CPU))==(ACCESS|BASE_MEM_CACHED_CPU));
  for(size_t i=0;i<len;i++) p[i]=(unsigned char)(i*37+n);
  sync_mem(c.fd,va,p,len,BASE_SYNCSET_OP_MSYNC,0);
  sync_mem(c.fd,va,p,len,BASE_SYNCSET_OP_CSYNC,0);
  for(size_t i=0;i<len;i++) CHECK(p[i]==(unsigned char)(i*37+n));
  if(n==0) {
   expect_query_error(c.fd,va+1,KBASE_MEM_QUERY_VA_SIZE);expect_query_error(c.fd,va,0xffff);
   sync_mem(c.fd,va+1,p,len,BASE_SYNCSET_OP_MSYNC,EINVAL);
   sync_mem(c.fd,va,p,len,0xff,EINVAL);
   sync_mem(c.fd,va,p,len+page,BASE_SYNCSET_OP_MSYNC,EINVAL);
   struct kbase_ioctl_mem_free f={.gpu_addr=va};errno=0;
   CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_FREE,&f)==-1 && errno==EINVAL);
  }
  CHECK(munmap(p,len)==0);expect_query_error(c.fd,va,KBASE_MEM_QUERY_VA_SIZE);
 }
 context_close(c);descriptor_check(before,0);
 puts("PASS native cached alloc/query/map, both sync directions, bounded errors and eight unmap lifetimes");
}

static void pending_case(void)
{
 int before=descriptors();struct context c=context_open(1);union kbase_ioctl_mem_alloc a=alloc(c.fd,2);
 void *p=mmap(NULL,page*3,PROT_READ|PROT_WRITE,MAP_SHARED,c.fd,(off_t)a.out.gpu_va);
 CHECK(p==MAP_FAILED);
 struct kbase_ioctl_mem_free f={.gpu_addr=a.out.gpu_va};CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_FREE,&f)==0);
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_FREE,&f)==-1 && errno==EINVAL);
 context_close(c);descriptor_check(before,0);
 puts("PASS pending-cookie map-size refusal, explicit free and double-free refusal");
}

static void dma_case(void)
{
 int before=descriptors();struct context c=context_open(1);size_t len=page*2;
 int ion=open("/dev/ion",O_RDONLY|O_CLOEXEC);CHECK(ion>=0);
 struct ion_allocation_data a={.len=len,.heap_id_mask=1,.flags=ION_FLAG_CACHED};
 CHECK(ioctl(ion,ION_IOC_ALLOC,&a)==0);CHECK(close(ion)==0);
 struct dma_buf_sync ds={.flags=DMA_BUF_SYNC_START|DMA_BUF_SYNC_RW};CHECK(ioctl(a.fd,DMA_BUF_IOCTL_SYNC,&ds)==0);
 unsigned char *p=mmap(NULL,len,PROT_READ|PROT_WRITE,MAP_SHARED,a.fd,0);CHECK(p!=MAP_FAILED);
 for(size_t i=0;i<len;i++) p[i]=(unsigned char)(i*13+7);
 ds.flags=DMA_BUF_SYNC_END|DMA_BUF_SYNC_RW;CHECK(ioctl(a.fd,DMA_BUF_IOCTL_SYNC,&ds)==0);CHECK(munmap(p,len)==0);
 int exported=(int)a.fd;
 union kbase_ioctl_mem_import im={.in={.flags=ACCESS|BASE_MEM_IMPORT_SHARED,
  .phandle=(uintptr_t)&exported,.type=BASE_MEM_IMPORT_TYPE_UMM}};
 CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_IMPORT,&im)==0);CHECK(im.out.va_pages==2 && (im.out.flags&BASE_MEM_NEED_MMAP));
 CHECK(close(exported)==0); /* only the importer retains this buffer now */
 errno=0;CHECK(fcntl(exported,F_GETFD)==-1 && errno==EBADF);
 p=mmap(NULL,len,PROT_READ|PROT_WRITE,MAP_SHARED,c.fd,(off_t)im.out.gpu_va);CHECK(p!=MAP_FAILED);
 uint64_t va=(uintptr_t)p;CHECK(query(c.fd,va,KBASE_MEM_QUERY_VA_SIZE)==2);
 CHECK(query(c.fd,va,KBASE_MEM_QUERY_COMMIT_SIZE)==2);
 sync_mem(c.fd,va,p,len,BASE_SYNCSET_OP_CSYNC,0);
 for(size_t i=0;i<len;i++) CHECK(p[i]==(unsigned char)(i*13+7));
 p[0]=0x51;p[len-1]=0xa2;sync_mem(c.fd,va,p,len,BASE_SYNCSET_OP_MSYNC,0);
 sync_mem(c.fd,va,p,len,BASE_SYNCSET_OP_CSYNC,0);CHECK(p[0]==0x51 && p[len-1]==0xa2);
 CHECK(munmap(p,len)==0);expect_query_error(c.fd,va,KBASE_MEM_QUERY_VA_SIZE);
 context_close(c);descriptor_check(before,1);
 puts("PASS dma-buf import/map/query, exporter-fd-close lifetime, data and both cache sync directions");
}

static void user_case(void)
{
 int before=descriptors();struct context c=context_open(1);size_t len=page*2;
 void *p=mmap(NULL,len,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);CHECK(p!=MAP_FAILED);memset(p,0x3c,len);
 struct base_mem_import_user_buffer b={.ptr=(uintptr_t)p,.length=len};
 union kbase_ioctl_mem_import im={.in={.flags=ACCESS|BASE_MEM_IMPORT_SHARED,.phandle=(uintptr_t)&b,.type=BASE_MEM_IMPORT_TYPE_USER_BUFFER}};
 CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_IMPORT,&im)==0);CHECK(im.out.va_pages==2 && (im.out.flags&BASE_MEM_NEED_MMAP));
 /* Noncoherent user imports are faulted-in here and pinned around external-resource jobs, not this context. */
 void *reservation=mmap(NULL,len,PROT_NONE,MAP_SHARED,c.fd,(off_t)im.out.gpu_va);CHECK(reservation!=MAP_FAILED);
 uint64_t va=(uintptr_t)reservation;CHECK(query(c.fd,va,KBASE_MEM_QUERY_VA_SIZE)==2);
 sync_mem(c.fd,va,p,len,BASE_SYNCSET_OP_MSYNC,EINVAL); /* legacy ABI only cache-syncs UMM imports */
 CHECK(munmap(reservation,len)==0);expect_query_error(c.fd,va,KBASE_MEM_QUERY_VA_SIZE);
 CHECK(munmap(p,len)==0);context_close(c);CHECK(descriptors()==before);
 puts("PASS aligned user-buffer import/query/reservation/free; unsupported user-import cache sync rejected");
}

static void errors_case(void)
{
 int before=descriptors();struct context c=context_open(1);
 union kbase_ioctl_mem_alloc a={.in={.va_pages=0,.commit_pages=0,.flags=ACCESS|BASE_MEM_SAME_VA}};
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_ALLOC,&a)==-1 && errno==ENOMEM);
 a=(union kbase_ioctl_mem_alloc){.in={.va_pages=1,.commit_pages=2,.flags=ACCESS|BASE_MEM_SAME_VA}};
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_ALLOC,&a)==-1 && errno==ENOMEM);
 a=(union kbase_ioctl_mem_alloc){.in={.va_pages=1,.commit_pages=1,.flags=ACCESS|BASEP_MEM_PERMANENT_KERNEL_MAPPING}};
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_ALLOC,&a)==-1 && errno==ENOMEM);
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_QUERY,NULL)==-1 && errno==EFAULT);
 expect_query_error(c.fd,0,KBASE_MEM_QUERY_VA_SIZE);
 int bad=-1;union kbase_ioctl_mem_import im={.in={.flags=ACCESS|BASE_MEM_IMPORT_SHARED,.phandle=(uintptr_t)&bad,.type=BASE_MEM_IMPORT_TYPE_UMM}};
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_IMPORT,&im)==-1 && errno==ENOMEM);
 im=(union kbase_ioctl_mem_import){.in={.flags=ACCESS,.phandle=1,.type=BASE_MEM_IMPORT_TYPE_UMM}};
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_IMPORT,&im)==-1 && errno==ENOMEM);
 im=(union kbase_ioctl_mem_import){.in={.flags=ACCESS,.phandle=(uintptr_t)&bad,.type=BASE_MEM_IMPORT_TYPE_INVALID}};
 errno=0;CHECK(ioctl(c.fd,KBASE_IOCTL_MEM_IMPORT,&im)==-1 && errno==ENOMEM);
 context_close(c);CHECK(descriptors()==before);
 puts("PASS zero/overcommit/kernel-only alloc, invalid query pointer/address and invalid import fd/pointer/type");
}

int main(int argc,char **argv)
{
 struct rlimit no_core={0};CHECK(setrlimit(RLIMIT_CORE,&no_core)==0);
 setvbuf(stdout,NULL,_IOLBF,0);page=(size_t)sysconf(_SC_PAGESIZE);CHECK(page==4096);
 const struct { const char *name; void (*run)(void); } cases[]={
  {"tracking",tracking_case},{"native",native_case},{"pending",pending_case},
  {"dmabuf",dma_case},{"user-buffer",user_case},{"errors",errors_case}};
 unsigned failed=0,ran=0;
 printf("kbase memory probe ABI=%zu page=%zu context_jobs=disabled\n",sizeof(void *)*8,page);
 for(unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
  if(argc>1 && strcmp(argv[1],cases[i].name)) continue;
  ran++;printf("CASE %s BEGIN\n",cases[i].name);pid_t pid=fork();CHECK(pid>=0);
  if(!pid) {cases[i].run();_exit(0);}
  int status;CHECK(waitpid(pid,&status,0)==pid);
  if(!WIFEXITED(status)||WEXITSTATUS(status)) {failed++;printf("CASE %s FAIL status=%d\n",cases[i].name,status);}
  else printf("CASE %s PASS\n",cases[i].name);
 }
 CHECK(ran>0);printf("RESULT: %s (%u cases, %u failed)\n",failed?"FAIL":"PASS",ran,failed);
 return failed?1:0;
}

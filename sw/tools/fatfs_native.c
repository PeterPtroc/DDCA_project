// Native test harness; the filesystem, disk adapter and SD driver are production C.
#include "ff.h"
#include "storage_disk.h"
#include <pthread.h>
#include <string.h>
#include <time.h>
static FATFS fs;
static pthread_mutex_t locks[FF_VOLUMES+1];
static int created[FF_VOLUMES+1];
int ff_mutex_create(int volume)
{
    if(volume<0 || volume>FF_VOLUMES) return 0;
    if(!created[volume]) {
        if(pthread_mutex_init(&locks[volume],NULL)) return 0;
        created[volume]=1;
    }
    return 1;
}
void ff_mutex_delete(int volume)
{
    if(volume>=0 && volume<=FF_VOLUMES && created[volume]) {
        (void)pthread_mutex_destroy(&locks[volume]);created[volume]=0;
    }
}
int ff_mutex_take(int volume)
{
    if(volume<0 || volume>FF_VOLUMES || !created[volume]) return 0;
    struct timespec deadline;
    if(!timespec_get(&deadline,TIME_UTC)) return 0;
    ++deadline.tv_sec;
    return pthread_mutex_timedlock(&locks[volume],&deadline)==0;
}
void ff_mutex_give(int volume) {(void)pthread_mutex_unlock(&locks[volume]);}
int ff_native_mount(const struct sd_transport *bus)
{
    FRESULT result=f_mount(NULL,"0:",0);
    if(result!=FR_OK) return result;
    if(bus) ptrocos_storage_disk_setup(bus);
    return f_mount(&fs,"0:",1);
}
int ff_native_unmount(void) {return f_mount(NULL,"0:",0);}
int ff_native_read(const char *path,uint32_t offset,void *data,unsigned capacity,unsigned *count)
{
    FIL file;*count=0;
    FRESULT result=f_open(&file,path,FA_READ);
    if(result!=FR_OK) return result;
    result=f_lseek(&file,offset);
    if(result==FR_OK) result=f_read(&file,data,capacity,count);
    FRESULT closed=f_close(&file);
    return result==FR_OK ? closed : result;
}
int ff_native_write(const char *path,const void *data,unsigned length,int append,unsigned *count)
{
    FIL file;*count=0;
    FRESULT result=f_open(&file,path,FA_WRITE|(append ? FA_OPEN_APPEND : FA_CREATE_ALWAYS));
    if(result!=FR_OK) return result;
    result=f_write(&file,data,length,count);
    if(result==FR_OK) result=f_sync(&file);
    FRESULT closed=f_close(&file);
    return result==FR_OK ? closed : result;
}
int ff_native_list(const char *path,char *data,unsigned capacity)
{
    DIR directory;FILINFO info;unsigned used=0;
    if(!capacity) return FR_INVALID_PARAMETER;
    data[0]=0;
    FRESULT result=f_opendir(&directory,path);
    if(result!=FR_OK) return result;
    for(;;) {
        result=f_readdir(&directory,&info);
        if(result!=FR_OK || !info.fname[0]) break;
        unsigned length=(unsigned)strlen(info.fname);
        if(length+used+2>capacity) {result=FR_INVALID_PARAMETER;break;}
        memcpy(data+used,info.fname,length);used+=length;data[used++]='\n';data[used]=0;
    }
    FRESULT closed=f_closedir(&directory);
    return result==FR_OK ? closed : result;
}
int ff_native_mkdir(const char *path) {return f_mkdir(path);}
int ff_native_unlink(const char *path) {return f_unlink(path);}
int ff_native_rename(const char *from,const char *to) {return f_rename(from,to);}
unsigned ff_native_sizeof(unsigned item)
{
    return item==0 ? sizeof(FATFS) : item==1 ? sizeof(FIL) : item==2 ? sizeof(FILINFO) : sizeof(struct sd_card);
}

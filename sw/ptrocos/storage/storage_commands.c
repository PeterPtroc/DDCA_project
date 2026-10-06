#include "storage_commands.h"
#include "storage_hw.h"
#include "storage_disk.h"
#include "board.h"
#include "FreeRTOS.h"
#include "semphr.h"
#include "ff.h"
#include <string.h>
static SemaphoreHandle_t lock;
static FATFS filesystem;
static unsigned mounted;
struct output {
    void (*write)(void *,const char *);
    void *context;
    volatile uint32_t *cancel;
};
static void put(struct output *o,const char *text) {o->write(o->context,text);}
static int same(const char *a,const char *b)
{
    while(*a && *a==*b) {++a;++b;}
    return *a==*b;
}
static void number(struct output *o,uint32_t value)
{
    char text[11];unsigned pos=10;text[10]=0;
    do {text[--pos]=(char)('0'+value%10U);value/=10U;} while(value);
    put(o,&text[pos]);
}
static void hex(struct output *o,uint32_t value)
{
    static const char digits[]="0123456789abcdef";char text[9];text[8]=0;
    for(unsigned i=0;i<8;i++) text[i]=digits[(value>>(28U-4U*i))&15U];
    put(o,text);
}
static void error(struct output *o,FRESULT result)
{
    put(o,"FatFs error=");number(o,result);put(o," SD=");
    put(o,sd_result_name(ptrocos_storage_disk_card()->last_error));put(o,"\r\n");
    if(!ptrocos_storage_disk_card()->initialized) mounted=0;
}
void ptrocos_storage_init(void)
{
    struct sd_transport bus;ptrocos_sd_transport(&bus);ptrocos_storage_disk_setup(&bus);
    lock=xSemaphoreCreateMutex();configASSERT(lock!=NULL);
}
static int mount(struct output *o)
{
    // Mount/unmount are serialized outside FatFs's per-volume lock.
    FRESULT result=f_mount(NULL,"0:",0);mounted=0;
    if(result==FR_OK) result=f_mount(&filesystem,"0:",1);
    if(result!=FR_OK) {error(o,result);return 0;}
    mounted=1;put(o,"FAT mounted type=");number(o,filesystem.fs_type);
    put(o," sectors=");number(o,ptrocos_storage_disk_card()->sectors);put(o,"\r\n");return 1;
}
static void check_file(struct output *o,const char *path)
{
    if(!mounted) {put(o,"mount the SD card first\r\n");return;}
    FIL file;FRESULT result=f_open(&file,path,FA_READ);
    if(result!=FR_OK) {error(o,result);return;}
    uint8_t buffer[512];uint32_t total=0;uint16_t crc=0xffffU;
    while(!*o->cancel) {
        UINT count;result=f_read(&file,buffer,sizeof(buffer),&count);
        if(result!=FR_OK || !count) break;
        crc=ptrocos_crc16(crc,buffer,count);total+=count;
        taskYIELD();
    }
    FRESULT closed=f_close(&file);
    if(result==FR_OK) result=closed;
    if(!*o->cancel) {
        if(result!=FR_OK) error(o,result);
        else {put(o,"FILE PASS bytes=");number(o,total);put(o," crc=");hex(o,crc);put(o,"\r\n");}
    }
}
int ptrocos_storage_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,volatile uint32_t *cancel)
{
    const char *name=argv[0];
    if(!same(name,"mount") && !same(name,"umount") && !same(name,"sdinfo") && !same(name,"fscheck")) return 0;
    struct output out={write,context,cancel};
    if(argc!=(same(name,"fscheck") ? 2U : 1U)) {put(&out,"usage: mount | umount | sdinfo | fscheck <path>\r\n");return 1;}
    while(xSemaphoreTake(lock,1)!=pdTRUE) if(*cancel) return 1;
    if(*cancel) {(void)xSemaphoreGive(lock);return 1;}
    ptrocos_sd_cancel_source(cancel);
    if(same(name,"mount")) (void)mount(&out);
    else if(same(name,"umount")) {
        FRESULT result=f_mount(NULL,"0:",0);mounted=0;
        if(result==FR_OK) put(&out,"FAT unmounted\r\n");else error(&out,result);
    } else if(same(name,"sdinfo")) {
        struct sd_card *card=ptrocos_storage_disk_card();
        put(&out,"SD status=");hex(&out,ptrocos_sd_status());put(&out," ready=");number(&out,sd_card_ready(card));
        put(&out," HC=");number(&out,card->high_capacity);put(&out," sectors=");number(&out,card->sectors);
        put(&out," reads=");number(&out,card->reads);put(&out," writes=");number(&out,card->writes);
        put(&out," exchanges=");number(&out,ptrocos_sd_exchanges());put(&out," error=");put(&out,sd_result_name(card->last_error));put(&out,"\r\n");
    } else check_file(&out,argv[1]);
    ptrocos_sd_cancel_source(NULL);
    configASSERT(xSemaphoreGive(lock)==pdTRUE);return 1;
}

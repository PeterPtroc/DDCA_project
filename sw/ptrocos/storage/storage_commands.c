#include "storage_commands.h"
#include "storage_hw.h"
#include "storage_disk.h"
#include "board.h"
#include "shell.h"
#include "FreeRTOS.h"
#include "semphr.h"
#include "ff.h"
#include <string.h>
#ifdef PTROCOS_ELF
#include "elf/elf_runtime.h"
#endif
#ifdef PTROCOS_MEDIA
#include "media/media_commands.h"
#endif
static SemaphoreHandle_t lock;
static FATFS filesystem;
static unsigned mounted;
struct output {
    void (*write)(void *,const char *);
    void (*write_byte)(void *,uint8_t);
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
#ifdef PTROCOS_ELF
struct elf_stream {FIL file;FRESULT error;volatile uint32_t *cancel;};
static int elf_cancelled(void *context) {struct elf_stream *s=context;return *s->cancel!=0;}
static int elf_read(void *context,uint32_t offset,void *data,unsigned bytes)
{
    struct elf_stream *s=context;UINT got=0;
    if(f_tell(&s->file)!=offset) s->error=f_lseek(&s->file,offset);
    if(s->error==FR_OK) s->error=f_read(&s->file,data,bytes,&got);
    if(*s->cancel) return ELF_CANCEL;
    if(s->error!=FR_OK) return ELF_IO;
    return got==bytes ? ELF_OK : ELF_FORMAT;
}
int ptrocos_storage_elf(const char *path,struct elf_image *image,void (*write)(void *,const char *),void *context,volatile uint32_t *cancel)
{
    memset(image,0,sizeof(*image));
    while(xSemaphoreTake(lock,1)!=pdTRUE) if(*cancel) return ELF_CANCEL;
    int result=ELF_IO;struct output out={write,NULL,context,cancel};
    if(*cancel) result=ELF_CANCEL;
    else if(!mounted) put(&out,"mount the SD card first\r\n");
    else {
        struct elf_stream stream;stream.cancel=cancel;
        ptrocos_sd_cancel_source(cancel);
        stream.error=f_open(&stream.file,path,FA_READ);
        if(stream.error==FR_OK) {
            struct elf_source source={(uint32_t)f_size(&stream.file),elf_read,elf_cancelled,&stream};
            struct elf_sink sink={ptrocos_elf_memory_write,ptrocos_elf_progress,NULL};
            result=ptrocos_elf_load(&source,&sink,image);
            FRESULT closed=f_close(&stream.file);
            if(stream.error==FR_OK) stream.error=closed;
        }
        if(stream.error!=FR_OK) {image->loaded=0;result=*cancel ? ELF_CANCEL : ELF_IO;}
        if(result!=ELF_OK && result!=ELF_CANCEL) {
            put(&out,"ELF load error=");number(&out,result);put(&out,"\r\n");
            if(stream.error!=FR_OK) error(&out,stream.error);
        }
        if(!ptrocos_storage_disk_card()->initialized) mounted=0;
        ptrocos_sd_cancel_source(NULL);
    }
    configASSERT(xSemaphoreGive(lock)==pdTRUE);return result;
}
#endif
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
static void file_info(struct output *o,const FILINFO *info)
{
    put(o,info->fattrib&AM_DIR ? "d " : "f ");number(o,(uint32_t)info->fsize);put(o," ");
    // Names remain UTF-8. Escape terminal controls without changing path parsing.
    static const char digits[]="0123456789abcdef";
    for(const uint8_t *p=(const uint8_t *)info->fname;*p && !*o->cancel;p++) {
        if(*p<32 || *p==127) {
            char escaped[]={ '\\','x',digits[*p>>4],digits[*p&15],0 };put(o,escaped);
        } else o->write_byte(o->context,*p);
    }
    put(o,"\r\n");
}
static void list(struct output *o,const char *path)
{
    if(!mounted) {put(o,"mount the SD card first\r\n");return;}
    FILINFO info;DIR directory;FRESULT result=f_opendir(&directory,path);
    if(result==FR_NO_PATH || result==FR_NO_FILE) {
        result=f_stat(path,&info);
        if(result!=FR_OK) {error(o,result);return;}
        if(!(info.fattrib&AM_DIR)) {file_info(o,&info);return;}
        result=f_opendir(&directory,path);
    }
    if(result!=FR_OK) {error(o,result);return;}
    while(!*o->cancel) {
        result=f_readdir(&directory,&info);
        if(result!=FR_OK || !info.fname[0]) break;
        file_info(o,&info);taskYIELD();
    }
    FRESULT closed=f_closedir(&directory);
    if(result==FR_OK) result=closed;
    if(!*o->cancel && result!=FR_OK) error(o,result);
}
static void cat(struct output *o,const char *path)
{
    if(!mounted) {put(o,"mount the SD card first\r\n");return;}
    FIL file;FRESULT result=f_open(&file,path,FA_READ);
    if(result!=FR_OK) {error(o,result);return;}
    uint8_t buffer[512];
    while(!*o->cancel) {
        UINT count;result=f_read(&file,buffer,sizeof(buffer),&count);
        if(result!=FR_OK || !count) break;
        for(UINT i=0;i<count && !*o->cancel;i++) o->write_byte(o->context,buffer[i]);
        taskYIELD();
    }
    FRESULT closed=f_close(&file);
    if(result==FR_OK) result=closed;
    if(!*o->cancel && result!=FR_OK) error(o,result);
}
static void hexdump(struct output *o,const char *path,uint32_t offset,uint32_t remaining)
{
    if(!mounted) {put(o,"mount the SD card first\r\n");return;}
    FIL file;FRESULT result=f_open(&file,path,FA_READ);
    if(result!=FR_OK) {error(o,result);return;}
    result=f_lseek(&file,offset);
    static const char digits[]="0123456789abcdef";
    while(result==FR_OK && remaining && !*o->cancel) {
        uint8_t buffer[16];char row[81];UINT count;unsigned pos=0;
        uint32_t address=(uint32_t)f_tell(&file);
        result=f_read(&file,buffer,remaining<16 ? (UINT)remaining : 16,&count);
        if(result!=FR_OK || !count) break;
        for(unsigned i=0;i<8;i++) row[pos++]=digits[(address>>(28U-4U*i))&15U];
        row[pos++]=' ';row[pos++]=' ';
        for(unsigned i=0;i<16;i++) {
            row[pos++]=i<count ? digits[buffer[i]>>4] : ' ';
            row[pos++]=i<count ? digits[buffer[i]&15] : ' ';
            row[pos++]=' ';if(i==7) row[pos++]=' ';
        }
        row[pos++]=' ';row[pos++]='|';
        for(unsigned i=0;i<16;i++) row[pos++]=i>=count ? ' ' : buffer[i]>=32 && buffer[i]<127 ? (char)buffer[i] : '.';
        row[pos++]='|';row[pos++]='\r';row[pos++]='\n';row[pos]=0;put(o,row);
        remaining-=count;taskYIELD();
    }
    FRESULT closed=f_close(&file);
    if(result==FR_OK) result=closed;
    if(!*o->cancel && result!=FR_OK) error(o,result);
}
int ptrocos_storage_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void (*write_byte)(void *,uint8_t),void *context,volatile uint32_t *cancel)
{
    if(!argc) return 0;
    const char *name=argv[0];
    unsigned command=same(name,"mount") ? 1 : same(name,"umount") ? 2 : same(name,"sdinfo") ? 3 :
        same(name,"fscheck") ? 4 : same(name,"ls") ? 5 : same(name,"cat") ? 6 : same(name,"hexdump") ? 7 :
#ifdef PTROCOS_MEDIA
        same(name,"bmp") ? 8 : same(name,"wav") ? 9 :
#ifdef PTROCOS_VIDEO
        same(name,"play") ? 10 :
#endif
#endif
        0;
    if(!command) return 0;
    struct output out={write,write_byte,context,cancel};uint32_t offset=0,count=256;
    if((command>=8 && argc!=2) || (command<=3 && argc!=1) || ((command==4 || command==6) && argc!=2) ||
       (command==5 && argc>2) || (command==7 && (argc<2 || argc>4 ||
       (argc>=3 && !shell_u32(argv[2],&offset)) || (argc==4 && !shell_u32(argv[3],&count)) || count>4096))) {
        put(&out,command==10 ? "usage: play <path>\r\n" : command>=8 ? "usage: bmp <path> | wav <path>\r\n" : command==5 ? "usage: ls [path]\r\n" : command==6 ? "usage: cat <path>\r\n" :
            command==7 ? "usage: hexdump <path> [offset] [count 0..4096] (decimal)\r\n" :
            "usage: mount | umount | sdinfo | fscheck <path>\r\n");return 1;
    }
    while(xSemaphoreTake(lock,1)!=pdTRUE) if(*cancel) return 1;
    if(*cancel) {(void)xSemaphoreGive(lock);return 1;}
    ptrocos_sd_cancel_source(cancel);
    if(command==1) (void)mount(&out);
    else if(command==2) {
        FRESULT result=f_mount(NULL,"0:",0);mounted=0;
        if(result==FR_OK) put(&out,"FAT unmounted\r\n");else error(&out,result);
    } else if(command==3) {
        struct sd_card *card=ptrocos_storage_disk_card();
        put(&out,"SD status=");hex(&out,ptrocos_sd_status());put(&out," ready=");number(&out,sd_card_ready(card));
        put(&out," HC=");number(&out,card->high_capacity);put(&out," sectors=");number(&out,card->sectors);
        put(&out," reads=");number(&out,card->reads);put(&out," writes=");number(&out,card->writes);
        put(&out," exchanges=");number(&out,ptrocos_sd_exchanges());put(&out," error=");put(&out,sd_result_name(card->last_error));put(&out,"\r\n");
    } else if(command==4) check_file(&out,argv[1]);
    else if(command==5) list(&out,argc==2 ? argv[1] : "0:/");
    else if(command==6) cat(&out,argv[1]);
    else if(command==7) hexdump(&out,argv[1],offset,count);
#ifdef PTROCOS_MEDIA
    else if(!mounted) put(&out,"mount the SD card first\r\n");
    else {
        FIL file;FRESULT result=f_open(&file,argv[1],FA_READ);
        if(result==FR_OK) {
            result=ptrocos_media_file(&file,command==10 ? 2 : command==9,write,context,cancel);
            FRESULT closed=f_close(&file);if(result==FR_OK) result=closed;
        }
        if(result!=FR_OK && !*cancel) error(&out,result);
    }
#endif
    if(!ptrocos_storage_disk_card()->initialized) mounted=0;
    ptrocos_sd_cancel_source(NULL);
    configASSERT(xSemaphoreGive(lock)==pdTRUE);return 1;
}

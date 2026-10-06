#include "audio.h"
#include "decode.h"
#include "board.h"
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include <string.h>
static SemaphoreHandle_t audio_lock;
static uint32_t reg(unsigned offset) {return PTROCOS_MMIO32(PTROCOS_AUDIO_BASE+offset);}
static void put(unsigned offset,uint32_t value) {PTROCOS_MMIO32(PTROCOS_AUDIO_BASE+offset)=value;}
static int cancelled(const struct ptrocos_audio *a) {return a->cancel && *a->cancel;}
void ptrocos_audio_init(void)
{
    audio_lock=xSemaphoreCreateMutex();configASSERT(audio_lock!=NULL);
    configASSERT(reg(20)==4096);
}
int ptrocos_audio_begin(struct ptrocos_audio *a,uint32_t rate,const volatile uint32_t *cancel)
{
    a->owned=0;a->started=0;a->cancel=cancel;
    if(rate<8000 || rate>48000) return MEDIA_FORMAT;
    while(xSemaphoreTake(audio_lock,1)!=pdTRUE) if(cancelled(a)) return MEDIA_CANCEL;
    a->owned=1;
    if(cancelled(a)) {ptrocos_audio_abort(a);return MEDIA_CANCEL;}
    put(8,2);put(4,rate);return MEDIA_OK;
}
void ptrocos_audio_abort(struct ptrocos_audio *a)
{
    if(a->owned) {put(8,2);a->owned=0;(void)xSemaphoreGive(audio_lock);}
}
int ptrocos_audio_feed(struct ptrocos_audio *a,const uint16_t *samples,unsigned count)
{
    if(!a->owned || count>4096) return MEDIA_OUTPUT;
    TickType_t begin=xTaskGetTickCount();
    while(reg(16)>4096-count) {
        if(cancelled(a)) return MEDIA_CANCEL;
        if(xTaskGetTickCount()-begin>=1000) return MEDIA_OUTPUT;
        vTaskDelay(1);
    }
    if(cancelled(a)) return MEDIA_CANCEL;
    for(unsigned i=0;i<count;i++) put(0,samples[i]);
    if(!a->started && reg(16)>=1024) {put(8,1);a->started=1;}
    return (reg(12)&0x38U) ? MEDIA_OUTPUT : MEDIA_OK;
}
int ptrocos_audio_end(struct ptrocos_audio *a)
{
    if(!a->owned) return MEDIA_OUTPUT;
    int result=MEDIA_OK;
    if(!a->started && reg(16)) {put(8,1);a->started=1;}
    put(8,4);TickType_t begin=xTaskGetTickCount();
    while(reg(12)&1U) {
        if(cancelled(a)) {result=MEDIA_CANCEL;break;}
        if(xTaskGetTickCount()-begin>=1000) {result=MEDIA_OUTPUT;break;}
        vTaskDelay(1);
    }
    if(!result && (reg(12)&0x38U)) result=MEDIA_OUTPUT;
    // Preserve completion counters for audio info until the next begin/abort.
    if(result) ptrocos_audio_abort(a);
    else {a->owned=0;(void)xSemaphoreGive(audio_lock);}
    return result;
}
static void number(void (*write)(void *,const char *),void *context,const char *label,uint32_t value)
{
    char text[11];unsigned p=10;text[10]=0;
    do {text[--p]=(char)('0'+value%10);value/=10;} while(value);
    write(context,label);write(context,&text[p]);
}
int ptrocos_audio_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel)
{
    if(strcmp(argv[0],"audio")) return 0;
    if(argc==2 && !strcmp(argv[1],"info")) {
        number(write,context,"audio rate=",reg(4));number(write,context," status=",reg(12));
        number(write,context," queued=",reg(16));number(write,context," played=",reg(24));
        number(write,context," underruns=",reg(28));write(context,"\r\n");
    } else if(argc==2 && !strcmp(argv[1],"test")) {
        struct ptrocos_audio a;int result=ptrocos_audio_begin(&a,8000,cancel);
        uint16_t samples[256];
        for(unsigned i=0;i<256;i++) samples[i]=(uint16_t)(i*257U);
        if(!result) result=ptrocos_audio_feed(&a,samples,256);
        if(!result) result=ptrocos_audio_end(&a);
        if(result) {ptrocos_audio_abort(&a);if(result!=MEDIA_CANCEL) write(context,"audio output error\r\n");}
        else write(context,"AUDIO PASS rate=8000 samples=256 underruns=0\r\n");
    } else write(context,"usage: audio info | test\r\n");
    return 1;
}

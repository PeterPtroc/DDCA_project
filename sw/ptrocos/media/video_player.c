#include "video_player.h"
#include "audio.h"
#include "graphics.h"
#include "FreeRTOS.h"
#include "task.h"
#include <string.h>
struct counters {uint32_t frames,read,displayed,dropped,elapsed,max_late,playing,rate,fps;};
static volatile struct counters last;
struct player {
    struct media_video header;
    struct ptrocos_video_canvas video;
    struct ptrocos_audio audio;
    const volatile uint32_t *cancel;
    uint32_t loaded,shown,start_tick;
    unsigned started;
};
static int cancelled(const struct player *p) {return p->cancel && *p->cancel;}
static int graphics_result(int result)
{return result==GFX_CANCELLED ? MEDIA_CANCEL : result ? MEDIA_OUTPUT : MEDIA_OK;}
static int show_due(struct player *p)
{
    if(cancelled(p)) return MEDIA_CANCEL;
    if(!p->started) return MEDIA_OK;
    uint32_t clock=xTaskGetTickCount()-p->start_tick;
    if(p->header.rate) {
        uint32_t space;unsigned running;
        int result=ptrocos_audio_query(&p->audio,&clock,&space,&running);if(result) return result;
    }
    uint32_t target=media_video_due(&p->header,clock);
    // If storage is late, present the newest complete available frame. Keeping
    // the old front indefinitely would prevent reclaiming a bounded ring.
    if(target>=p->loaded) target=p->loaded-1;
    if(target<=p->shown) return MEDIA_OK;
    int result=graphics_result(ptrocos_graphics_video_present(&p->video,target));if(result) return result;
    last.dropped+=target-p->shown-1;last.displayed++;p->shown=target;
    uint32_t elapsed=xTaskGetTickCount()-p->start_tick;
    uint32_t deadline=(uint32_t)((uint64_t)target*1000/p->header.fps);
    uint32_t late=elapsed>deadline ? elapsed-deadline : 0;
    if(late>last.max_late) last.max_late=late;
    return MEDIA_OK;
}
static int bitmap(void *context,const uint8_t *bits)
{
    struct player *p=context;
    return graphics_result(ptrocos_graphics_video_write(&p->video,p->loaded,bits,p->cancel));
}
static int pcm(void *context,const uint16_t *samples,unsigned count)
{
    struct player *p=context;
    int result=ptrocos_audio_feed(&p->audio,samples,count);
    return result ? result : show_due(p);
}
static void number(void (*write)(void *,const char *),void *context,const char *label,uint32_t value)
{
    char text[11];unsigned pos=10;text[10]=0;
    do {text[--pos]=(char)('0'+value%10);value/=10;} while(value);
    write(context,label);write(context,text+pos);
}
static void info(void (*write)(void *,const char *),void *context,const char *prefix)
{
    number(write,context,prefix,last.fps);number(write,context," frames=",last.frames);
    number(write,context," read=",last.read);number(write,context," displayed=",last.displayed);
    number(write,context," dropped=",last.dropped);number(write,context," elapsed_ms=",last.elapsed);
    number(write,context," max_late_ms=",last.max_late);number(write,context," audio_rate=",last.rate);
    number(write,context," playing=",last.playing);write(context,"\r\n");
}
int ptrocos_video_play(const struct media_source *source,struct media_work *work,
    void (*write)(void *,const char *),void *context,const volatile uint32_t *cancel)
{
    struct player p={0};p.cancel=cancel;
    int result=media_video_open(source,&p.header);if(result) return result;
    result=graphics_result(ptrocos_graphics_video_begin(&p.video,cancel));if(result) return result;
    last=(struct counters){.frames=p.header.frames,.fps=p.header.fps,.rate=p.header.rate,.playing=1};
    if(p.header.rate) {
        result=ptrocos_audio_begin(&p.audio,p.header.rate,cancel);
        if(result) goto done;
        p.audio.manual_start=1;
    }
    number(write,context,"PTV fps=",p.header.fps);number(write,context," frames=",p.header.frames);
    number(write,context," audio_rate=",p.header.rate);write(context,"; Ctrl+C cancels\r\n");
    unsigned prefilled=0;
    while(p.loaded<p.header.frames && (p.header.rate ? prefilled<1024 : p.loaded<2)) {
        result=media_video_frame(source,&p.header,p.loaded,work,bitmap,pcm,&p);if(result) goto done;
        prefilled+=media_video_audio_count(&p.header,p.loaded);p.loaded++;last.read=p.loaded;
    }
    if(cancelled(&p)) {result=MEDIA_CANCEL;goto done;}
    result=graphics_result(ptrocos_graphics_video_present(&p.video,0));if(result) goto done;
    last.displayed=1;p.start_tick=xTaskGetTickCount();p.started=1;
    if(p.header.rate) {
        result=ptrocos_audio_start(&p.audio);if(result) goto done;
        if(p.loaded==p.header.frames) {result=ptrocos_audio_finish(&p.audio);if(result) goto done;}
    }
    for(;;) {
        uint32_t played=0,space=4096;unsigned running=0;
        if(p.header.rate) {
            result=ptrocos_audio_query(&p.audio,&played,&space,&running);if(result) break;
        }
        result=show_due(&p);if(result) break;
        last.elapsed=xTaskGetTickCount()-p.start_tick;
        if(p.loaded==p.header.frames && (p.header.rate ? !running :
           last.elapsed>=((uint64_t)p.header.frames*1000+p.header.fps-1)/p.header.fps)) break;
        if(p.loaded<p.header.frames && p.loaded-p.shown<7 &&
           space>=media_video_audio_count(&p.header,p.loaded)) {
            result=media_video_frame(source,&p.header,p.loaded,work,bitmap,pcm,&p);if(result) break;
            p.loaded++;last.read=p.loaded;
            if(p.loaded==p.header.frames && p.header.rate) {
                result=ptrocos_audio_finish(&p.audio);if(result) break;
            }
        } else vTaskDelay(1);
    }
    if(!result && p.header.rate) result=ptrocos_audio_end(&p.audio);
    if(!result && last.displayed+last.dropped!=p.header.frames) result=MEDIA_OUTPUT;
done:
    if(result) ptrocos_audio_abort(&p.audio);
    int close_result=graphics_result(ptrocos_graphics_video_close(&p.video));
    if(!result) result=close_result;
    last.playing=0;
    if(!result) info(write,context,"PTV played fps=");
    return result;
}
static struct media_work diagnostic_work;
static const uint8_t diagnostic_header[32]={'P','T','V','1',32,0,1,0,160,0,120,0,15,0,0,0,4,0,0,0,0x40,0x1f,0,0,0x60,9,0,0,0,0,0,0};
static int diagnostic_read(void *context,uint32_t offset,void *data,unsigned count)
{
    (void)context;uint8_t *out=data;
    if(offset<32) {
        if(offset+count>32) return MEDIA_FORMAT;
        memcpy(data,diagnostic_header+offset,count);return MEDIA_OK;
    }
    uint32_t pos=32;
    for(unsigned frame=0;frame<4;frame++) {
        unsigned first=frame*8000/15,amount=(frame+1)*8000/15-first;
        if(offset>=pos && offset+count<=pos+2400) {
            for(unsigned i=0;i<count;i++) {
                unsigned byte=offset+i-pos,y=byte/20,x=byte%20*8;uint8_t value=0;
                for(unsigned b=0;b<8;b++) if(((x+b+frame*13)/16+y/12+frame)&1U) value|=(uint8_t)(1U<<b);
                out[i]=value;
            }
            return MEDIA_OK;
        }
        pos+=2400;
        if(offset>=pos && offset+count<=pos+amount*2) {
            for(unsigned i=0;i<count;i++) {
                unsigned byte=offset+i-pos;uint16_t sample=(uint16_t)((first+byte/2)*257U);
                out[i]=(uint8_t)(sample>>((byte&1U)*8));
            }
            return MEDIA_OK;
        }
        pos+=amount*2;
    }
    return MEDIA_FORMAT;
}
int ptrocos_video_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel)
{
    if(strcmp(argv[0],"video") || argc==1) return 0;
    if(argc==2 && !strcmp(argv[1],"info")) info(write,context,"video fps=");
    else if(argc==2 && !strcmp(argv[1],"test")) {
        struct media_source source={32+4*2400+(4*8000/15)*2,diagnostic_read,0,0};
        int result=ptrocos_video_play(&source,&diagnostic_work,write,context,cancel);
        if(result && result!=MEDIA_CANCEL) write(context,"video output error\r\n");
    } else write(context,"usage: video info | test; play <path>\r\n");
    return 1;
}

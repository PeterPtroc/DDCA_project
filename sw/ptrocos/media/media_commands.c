#include "media_commands.h"
#include "decode.h"
#include "audio.h"
#include "graphics.h"
#include "FreeRTOS.h"
#include "task.h"
#ifdef PTROCOS_VIDEO
#include "video_player.h"
#endif
// Storage serialization protects this workspace and each file stream.
static struct media_work work;
struct stream {FIL *file;FRESULT error;const volatile uint32_t *cancel;};
static int cancelled(void *context) {struct stream *s=context;return s->cancel && *s->cancel;}
static int read_at(void *context,uint32_t offset,void *buffer,unsigned count)
{
    struct stream *s=context;UINT got=0;
    if(f_tell(s->file)!=offset) s->error=f_lseek(s->file,offset);
    if(s->error==FR_OK) s->error=f_read(s->file,buffer,count,&got);
    if(cancelled(s)) return MEDIA_CANCEL;
    if(s->error!=FR_OK) return MEDIA_IO;
    return got==count ? MEDIA_OK : MEDIA_FORMAT;
}
struct drawing {struct ptrocos_canvas canvas;const volatile uint32_t *cancel;};
static int draw_row(void *context,unsigned row,const uint32_t *pixels)
{
    struct drawing *d=context;int result=ptrocos_graphics_row(&d->canvas,row,pixels,d->cancel);
    if(!(row&7)) vTaskDelay(1);
    return result==GFX_CANCELLED ? MEDIA_CANCEL : result ? MEDIA_OUTPUT : MEDIA_OK;
}
static int feed(void *context,const uint16_t *samples,unsigned count) {return ptrocos_audio_feed(context,samples,count);}
static void number(void (*write)(void *,const char *),void *context,const char *name,uint32_t n)
{
    char text[11];unsigned p=10;text[10]=0;
    do {text[--p]=(char)('0'+n%10);n/=10;} while(n);
    write(context,name);write(context,&text[p]);
}
FRESULT ptrocos_media_file(FIL *file,unsigned kind,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel)
{
    struct stream stream={file,FR_OK,cancel};
    struct media_source source={(uint32_t)f_size(file),read_at,cancelled,&stream};int result;
#ifdef PTROCOS_VIDEO
    if(kind==2) result=ptrocos_video_play(&source,&work,write,context,cancel);
    else
#endif
    if(kind==1) {
        struct media_wav header;struct ptrocos_audio audio={0};
        result=media_wav_open(&source,&header);
        if(!result) {
            number(write,context,"WAV rate=",header.rate);number(write,context," channels=",header.channels);
            number(write,context," bits=",header.bits);number(write,context," frames=",header.frames);
            write(context,"; Ctrl+C cancels\r\n");
            result=ptrocos_audio_begin(&audio,header.rate,cancel);
        }
        if(!result) result=media_wav_play(&source,&header,&work,feed,&audio);
        if(!result) result=ptrocos_audio_end(&audio);
        if(result) ptrocos_audio_abort(&audio);
        else {number(write,context,"WAV played frames=",header.frames);write(context,"\r\n");}
    } else {
        struct media_bmp header;struct drawing d={{0},cancel};
        result=media_bmp_open(&source,&header);
        if(!result) {
            number(write,context,"BMP width=",header.width);number(write,context," height=",header.height);
            number(write,context," bits=",header.bits);write(context,"; Ctrl+C cancels\r\n");
            int g=ptrocos_graphics_begin(&d.canvas,cancel);
            result=g==GFX_CANCELLED ? MEDIA_CANCEL : g ? MEDIA_OUTPUT : MEDIA_OK;
        }
        if(!result) result=media_bmp_draw(&source,&header,&work,draw_row,&d);
        if(!result && cancelled(&stream)) result=MEDIA_CANCEL;
        if(!result) result=ptrocos_graphics_present(&d.canvas) ? MEDIA_OUTPUT : MEDIA_OK;
        if(result) ptrocos_graphics_abort(&d.canvas);
        else write(context,"BMP displayed\r\n");
    }
    if(result==MEDIA_FORMAT) write(context,"unsupported or malformed media file\r\n");
    else if(result==MEDIA_OUTPUT) write(context,"media output error\r\n");
    return stream.error;
}

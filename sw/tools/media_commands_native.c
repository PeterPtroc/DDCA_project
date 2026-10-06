// Native sinks validate stream ownership; full SoC tests use actual DDR/audio RTL.
#include "graphics.h"
#include "media/audio.h"
#include "media/decode.h"
#include "FreeRTOS.h"
#include <assert.h>
#include <string.h>
static uint32_t back[480][320],front[480][320];
static uint16_t emitted[20000];
static unsigned frames,rows,samples,audio_done;
static void (*hook)(unsigned,unsigned);
void media_native_hook(void (*callback)(unsigned,unsigned)) {hook=callback;}
void media_native_reset(void) {frames=rows=samples=audio_done=0;memset(front,0,sizeof(front));}
unsigned media_native_count(unsigned field) {return field==0 ? frames : field==1 ? rows : field==2 ? samples : audio_done;}
const void *media_native_pixels(void) {return front;}
const void *media_native_samples(void) {return emitted;}
void ptrocos_graphics_init(void) { }
int ptrocos_graphics_begin(struct ptrocos_canvas *canvas,const volatile uint32_t *cancel)
{canvas->owned=0;if(cancel && *cancel) return GFX_CANCELLED;canvas->owned=1;rows=0;return GFX_OK;}
int ptrocos_graphics_row(struct ptrocos_canvas *canvas,unsigned row,const uint32_t *pixels,const volatile uint32_t *cancel)
{
    assert(canvas->owned && row<480);if(hook) hook(0,row);
    if(cancel && *cancel) return GFX_CANCELLED;
    memcpy(back[row],pixels,1280);rows++;return GFX_OK;
}
int ptrocos_graphics_present(struct ptrocos_canvas *canvas)
{assert(canvas->owned && rows==480);memcpy(front,back,sizeof(front));frames++;canvas->owned=0;return GFX_OK;}
void ptrocos_graphics_abort(struct ptrocos_canvas *canvas) {canvas->owned=0;}
#ifndef PTROCOS_VIDEO
void ptrocos_audio_init(void) { }
int ptrocos_audio_begin(struct ptrocos_audio *a,uint32_t rate,const volatile uint32_t *cancel)
{assert(rate>=8000 && rate<=48000);a->owned=1;a->cancel=cancel;samples=0;audio_done=0;return MEDIA_OK;}
int ptrocos_audio_feed(struct ptrocos_audio *a,const uint16_t *values,unsigned count)
{
    assert(a->owned && samples+count<=20000);if(hook) hook(1,samples);
    if(a->cancel && *a->cancel) return MEDIA_CANCEL;
    memcpy(emitted+samples,values,count*2);samples+=count;return MEDIA_OK;
}
int ptrocos_audio_end(struct ptrocos_audio *a) {assert(a->owned);audio_done=1;a->owned=0;return MEDIA_OK;}
void ptrocos_audio_abort(struct ptrocos_audio *a) {if(a->owned) {a->owned=0;audio_done=0;}}
void vTaskDelay(unsigned ticks) {(void)ticks;storage_native_yield();}
#endif

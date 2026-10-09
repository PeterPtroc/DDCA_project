// Deterministic sink clock: the actual player runs with graphics/audio adapters.
#include "media/video_player.h"
#include "media/audio.h"
#include "graphics.h"
#include <assert.h>
#include <string.h>
static uint32_t tick,rate,phase,played,write_at,queued;
static unsigned running,finishing,gfx_owned,audio_owned,seed,front,has_front,gfx_enabled;
static uint8_t slots[8][2400];
#ifndef VIDEO_NATIVE_MAX_SAMPLES
#define VIDEO_NATIVE_MAX_SAMPLES 2000000
#endif
static uint16_t fifo[4096],emitted[VIDEO_NATIVE_MAX_SAMPLES];
static uint32_t slot_frame[8];
static uint32_t presented[200000],present_ticks[200000];
static unsigned shown,samples;
static int close_error;
static void (*hook)(unsigned,unsigned,const void *);
void video_native_hook(void (*callback)(unsigned,unsigned,const void *)) {hook=callback;}
void video_native_close_error(int result) {close_error=result;}
void video_native_reset(uint32_t start)
{
    assert(!gfx_owned && !audio_owned);tick=start;rate=phase=played=write_at=queued=0;
    running=finishing=shown=samples=0;close_error=0;
}
void video_native_advance(unsigned ticks)
{
    while(ticks--) {
        tick++;
        if(!running) continue;
        phase+=rate;
        while(phase>=1000 && running) {
            phase-=1000;
            if(queued) {
                uint16_t value=fifo[played&4095U];played++;queued--;
                assert(samples<VIDEO_NATIVE_MAX_SAMPLES);emitted[samples++]=value;
                if(hook) hook(3,played,&value);
            } else if(finishing) running=0;
            else {if(hook) hook(4,played,0);running=0;}
        }
    }
}
void vTaskDelay(unsigned ticks) {video_native_advance(ticks);}
unsigned xTaskGetTickCount(void) {return tick;}
#ifndef VIDEO_NATIVE_STORAGE
void storage_native_yield(void) { }
#endif
unsigned video_native_value(unsigned index)
{
    return index==0 ? shown : index==1 ? samples : index==2 ? gfx_owned :
        index==3 ? audio_owned : index==4 ? tick : index==5 ? queued : index==6 ? front :
        index==7 ? running : gfx_enabled;
}
const uint32_t *video_native_frames(void) {return presented;}
const uint32_t *video_native_ticks(void) {return present_ticks;}
const uint16_t *video_native_samples(void) {return emitted;}
int ptrocos_graphics_video_begin(struct ptrocos_video_canvas *v,const volatile uint32_t *cancel)
{
    if(cancel && *cancel) return GFX_CANCELLED;
    if(gfx_owned) return GFX_TIMEOUT;
    gfx_owned=1;v->canvas.owned=1;seed=has_front ? (front+1)&7U : 0;v->seed=seed;return GFX_OK;
}
int ptrocos_graphics_video_write(struct ptrocos_video_canvas *v,uint32_t frame,
    const uint8_t *bits,const volatile uint32_t *cancel)
{
    assert(gfx_owned && v->canvas.owned);unsigned slot=(v->seed+frame)&7U;
    assert(!has_front || slot!=front);
    if(cancel && *cancel) return GFX_CANCELLED;
    memcpy(slots[slot],bits,2400);slot_frame[slot]=frame;
    if(hook) hook(0,frame,bits);
    return GFX_OK;
}
int ptrocos_graphics_video_present(struct ptrocos_video_canvas *v,uint32_t frame)
{
    assert(gfx_owned && v->canvas.owned);unsigned slot=(v->seed+frame)&7U;
    assert(slot_frame[slot]==frame);
    video_native_advance(16-(tick%16));front=slot;has_front=1;gfx_enabled=1;
    assert(shown<200000);presented[shown]=frame;present_ticks[shown++]=tick;
    if(hook) hook(1,frame,slots[slot]);
    return GFX_OK;
}
int ptrocos_graphics_video_close(struct ptrocos_video_canvas *v)
{
    if(v->canvas.owned) {
        video_native_advance(16-(tick%16));gfx_enabled=0;
        if(hook) hook(5,0,0);
        gfx_owned=0;v->canvas.owned=0;
    }
    return close_error;
}
int ptrocos_audio_begin(struct ptrocos_audio *a,uint32_t hz,const volatile uint32_t *cancel)
{
    if(cancel && *cancel) return MEDIA_CANCEL;
    if(audio_owned) return MEDIA_OUTPUT;
    audio_owned=1;a->owned=1;a->started=0;a->manual_start=0;a->cancel=cancel;
    rate=hz;phase=played=write_at=queued=0;running=finishing=0;return MEDIA_OK;
}
int ptrocos_audio_feed(struct ptrocos_audio *a,const uint16_t *data,unsigned count)
{
    assert(audio_owned && a->owned && count<=256 && queued+count<=4096);
    if(a->cancel && *a->cancel) return MEDIA_CANCEL;
    for(unsigned i=0;i<count;i++) fifo[write_at++&4095U]=data[i];
    queued+=count;if(hook) hook(2,count,data);return MEDIA_OK;
}
int ptrocos_audio_start(struct ptrocos_audio *a)
{
    assert(a->owned && queued && !running);running=1;a->started=1;return MEDIA_OK;
}
int ptrocos_audio_query(const struct ptrocos_audio *a,uint32_t *n,uint32_t *space,unsigned *active)
{
    if(a->cancel && *a->cancel) return MEDIA_CANCEL;
    assert(a->owned);*n=played;*space=4096-queued;*active=running;return MEDIA_OK;
}
int ptrocos_audio_finish(struct ptrocos_audio *a)
{assert(a->owned && running);finishing=1;return MEDIA_OK;}
int ptrocos_audio_end(struct ptrocos_audio *a)
{assert(a->owned && !running && !queued);a->owned=0;audio_owned=0;return MEDIA_OK;}
void ptrocos_audio_abort(struct ptrocos_audio *a)
{if(a->owned) {a->owned=0;audio_owned=0;running=queued=0;}}

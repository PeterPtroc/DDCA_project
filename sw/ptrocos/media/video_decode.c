#include "video_decode.h"
#include <string.h>
static unsigned le16(const uint8_t *p) {return p[0]|((unsigned)p[1]<<8);}
static uint32_t le32(const uint8_t *p) {return le16(p)|((uint32_t)le16(p+2)<<16);}
static int read_at(const struct media_source *s,uint32_t offset,void *data,unsigned count)
{
    if(s->cancelled && s->cancelled(s->context)) return MEDIA_CANCEL;
    if(offset>s->size || count>s->size-offset) return MEDIA_FORMAT;
    return s->read(s->context,offset,data,count);
}
int media_video_open(const struct media_source *s,struct media_video *v)
{
    uint8_t h[32];int result=read_at(s,0,h,sizeof(h));if(result) return result;
    v->fps=le32(h+12);v->frames=le32(h+16);v->rate=le32(h+20);
    if(memcmp(h,"PTV1",4) || le16(h+4)!=32 || le16(h+6)!=(v->rate ? 1U : 0U) ||
       le16(h+8)!=160 || le16(h+10)!=120 || v->fps<10 || v->fps>30 ||
       !v->frames || v->frames>v->fps*3600U ||
       (v->rate && (v->rate<8000 || v->rate>16000)) || le32(h+24)!=2400 || le32(h+28))
        return MEDIA_FORMAT;
    uint64_t samples=(uint64_t)v->frames*v->rate/v->fps;
    uint64_t length=32+(uint64_t)v->frames*2400+samples*2;
    return length==s->size ? MEDIA_OK : MEDIA_FORMAT;
}
unsigned media_video_audio_count(const struct media_video *v,uint32_t frame)
{
    return (unsigned)(((uint64_t)(frame+1)*v->rate/v->fps)-((uint64_t)frame*v->rate/v->fps));
}
uint32_t media_video_due(const struct media_video *v,uint32_t clock_units)
{
    uint64_t frame=(uint64_t)clock_units*v->fps/(v->rate ? v->rate : 1000U);
    return frame<v->frames ? (uint32_t)frame : v->frames-1;
}
int media_video_frame(const struct media_source *s,const struct media_video *v,uint32_t frame,
    struct media_work *work,int (*bitmap)(void *,const uint8_t *),
    int (*pcm)(void *,const uint16_t *,unsigned),void *context)
{
    if(frame>=v->frames) return MEDIA_FORMAT;
    uint64_t offset=32+(uint64_t)frame*2400+((uint64_t)frame*v->rate/v->fps)*2;
    if(offset>UINT32_MAX) return MEDIA_FORMAT;
    uint32_t pos=(uint32_t)offset;
    int result=read_at(s,pos,work->input,2400);if(result) return result;
    result=bitmap(context,work->input);if(result) return result;
    pos+=2400;unsigned remaining=media_video_audio_count(v,frame);
    while(remaining) {
        unsigned count=remaining>256 ? 256 : remaining;
        result=read_at(s,pos,work->input,count*2);if(result) return result;
        for(unsigned i=0;i<count;i++) work->output.samples[i]=(uint16_t)le16(work->input+i*2);
        result=pcm(context,work->output.samples,count);if(result) return result;
        pos+=count*2;remaining-=count;
    }
    return MEDIA_OK;
}

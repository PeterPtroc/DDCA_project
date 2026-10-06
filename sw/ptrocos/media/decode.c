#include "decode.h"
#include <string.h>
static uint32_t le32(const uint8_t *p) {return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static unsigned le16(const uint8_t *p) {return p[0]|((unsigned)p[1]<<8);}
static int read_at(const struct media_source *s,uint32_t offset,void *buffer,unsigned count)
{
    if(s->cancelled && s->cancelled(s->context)) return MEDIA_CANCEL;
    if(offset>s->size || count>s->size-offset) return MEDIA_FORMAT;
    return s->read(s->context,offset,buffer,count);
}
int media_bmp_open(const struct media_source *s,struct media_bmp *b)
{
    uint8_t h[54];int result=read_at(s,0,h,sizeof(h));if(result) return result;
    uint32_t length=le32(h+2),dib=le32(h+14),height=le32(h+22);
    b->width=le32(h+18);b->top_down=height>>31;b->height=b->top_down ? 0U-height : height;
    b->offset=le32(h+10);b->bits=le16(h+28);
    if(h[0]!='B' || h[1]!='M' || length>s->size || dib<40 || dib>124 ||
       b->offset<14+dib || b->offset>length || le16(h+26)!=1 || le32(h+30)!=0 ||
       (b->bits!=24 && b->bits!=32) || !b->width || b->width>640 || !b->height || b->height>480)
        return MEDIA_FORMAT;
    b->stride=(b->width*(b->bits/8)+3)&~3U;
    uint32_t bytes=b->stride*b->height,image=le32(h+34);
    if(bytes>length-b->offset || (image && (image<bytes || image>length-b->offset))) return MEDIA_FORMAT;
    return MEDIA_OK;
}
int media_bmp_draw(const struct media_source *s,const struct media_bmp *b,struct media_work *w,
    int (*row)(void *,unsigned,const uint32_t *),void *context)
{
    for(unsigned y=0;y<480;y++) {
        if(s->cancelled && s->cancelled(s->context)) return MEDIA_CANCEL;
        memset(w->output.pixels,0,sizeof(w->output.pixels));
        if(y<b->height) {
            unsigned source_y=y;
            int result=read_at(s,b->offset+source_y*b->stride,w->input,b->width*(b->bits/8));
            if(result) return result;
            for(unsigned x=0;x<b->width;x++) {
                const uint8_t *p=w->input+x*(b->bits/8);
                uint16_t rgb=(uint16_t)(((p[2]>>3)<<11)|((p[1]>>2)<<5)|(p[0]>>3));
                w->output.pixels[x/2]|=(uint32_t)rgb<<((x&1)*16);
            }
        }
        unsigned destination=y<b->height && !b->top_down ? b->height-1-y : y;
        int result=row(context,destination,w->output.pixels);if(result) return result;
    }
    return MEDIA_OK;
}
int media_wav_open(const struct media_source *s,struct media_wav *w)
{
    uint8_t h[16];int result=read_at(s,0,h,12);if(result) return result;
    uint32_t length=le32(h+4),pos=12;unsigned fmt=0,data=0;
    if(memcmp(h,"RIFF",4) || memcmp(h+8,"WAVE",4) || length<4 || length>s->size-8) return MEDIA_FORMAT;
    uint32_t end=length+8;
    while(pos<end) {
        if(end-pos<8) return MEDIA_FORMAT;
        result=read_at(s,pos,h,8);if(result) return result;
        uint32_t bytes=le32(h+4);pos+=8;
        if(bytes>end-pos || (bytes&1)>end-pos-bytes) return MEDIA_FORMAT;
        if(!memcmp(h,"fmt ",4)) {
            if(fmt || bytes<16) return MEDIA_FORMAT;
            result=read_at(s,pos,h,16);if(result) return result;
            w->channels=le16(h+2);w->rate=le32(h+4);w->align=le16(h+12);w->bits=le16(h+14);
            if(le16(h)!=1 || (w->channels!=1 && w->channels!=2) || (w->bits!=8 && w->bits!=16) ||
               w->rate<8000 || w->rate>48000 || w->align!=w->channels*(w->bits/8) ||
               le32(h+8)!=w->rate*w->align) return MEDIA_FORMAT;
            fmt=1;
        } else if(!memcmp(h,"data",4)) {
            if(data || !bytes) return MEDIA_FORMAT;
            w->offset=pos;w->bytes=bytes;data=1;
        }
        pos+=bytes+(bytes&1);
    }
    if(!fmt || !data || w->bytes%w->align) return MEDIA_FORMAT;
    w->frames=w->bytes/w->align;return MEDIA_OK;
}
static int32_t pcm(const uint8_t *p,unsigned bits)
{
    if(bits==8) return ((int32_t)p[0]-128)*256;
    unsigned raw=le16(p);return (raw&32768) ? (int32_t)raw-65536 : (int32_t)raw;
}
int media_wav_play(const struct media_source *s,const struct media_wav *w,struct media_work *work,
    int (*samples)(void *,const uint16_t *,unsigned),void *context)
{
    uint32_t pos=w->offset,remaining=w->frames;
    while(remaining) {
        unsigned count=remaining>256 ? 256 : remaining;
        int result=read_at(s,pos,work->input,count*w->align);if(result) return result;
        uint16_t *out=work->output.samples;
        for(unsigned i=0;i<count;i++) {
            const uint8_t *p=work->input+i*w->align;int32_t sample=pcm(p,w->bits);
            if(w->channels==2) sample=(sample+pcm(p+w->bits/8,w->bits))/2;
            out[i]=(uint16_t)(sample+32768);
        }
        result=samples(context,out,count);if(result) return result;
        pos+=count*w->align;remaining-=count;
    }
    return MEDIA_OK;
}

#ifndef PTROCOS_MEDIA_DECODE_H
#define PTROCOS_MEDIA_DECODE_H
#include <stdint.h>
enum { MEDIA_OK=0, MEDIA_FORMAT=1, MEDIA_IO=2, MEDIA_CANCEL=3, MEDIA_OUTPUT=4 };
struct media_source {
    uint32_t size;
    int (*read)(void *context,uint32_t offset,void *buffer,unsigned count);
    int (*cancelled)(void *context);
    void *context;
};
struct media_bmp {uint32_t width,height,offset,stride;unsigned bits,top_down;};
struct media_wav {uint32_t rate,offset,bytes,frames;unsigned channels,bits,align;};
// Bounded workspace: one source scanline and one 640-pixel output scanline.
struct media_work {uint8_t input[2560];union {uint32_t pixels[320];uint16_t samples[640];} output;};
int media_bmp_open(const struct media_source *s,struct media_bmp *bmp);
int media_bmp_draw(const struct media_source *s,const struct media_bmp *bmp,struct media_work *work,
    int (*row)(void *,unsigned,const uint32_t *),void *context);
int media_wav_open(const struct media_source *s,struct media_wav *wav);
int media_wav_play(const struct media_source *s,const struct media_wav *wav,struct media_work *work,
    int (*samples)(void *,const uint16_t *,unsigned),void *context);
#endif

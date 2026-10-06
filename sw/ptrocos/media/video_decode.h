#ifndef PTROCOS_VIDEO_DECODE_H
#define PTROCOS_VIDEO_DECODE_H
#include "decode.h"
#define MEDIA_VIDEO_WIDTH 160U
#define MEDIA_VIDEO_HEIGHT 120U
#define MEDIA_VIDEO_BYTES 2400U
struct media_video {uint32_t fps,frames,rate;};
int media_video_open(const struct media_source *s,struct media_video *v);
unsigned media_video_audio_count(const struct media_video *v,uint32_t frame);
uint32_t media_video_due(const struct media_video *v,uint32_t clock_units);
int media_video_frame(const struct media_source *s,const struct media_video *v,uint32_t frame,
    struct media_work *work,int (*bitmap)(void *,const uint8_t *),
    int (*pcm)(void *,const uint16_t *,unsigned),void *context);
#endif

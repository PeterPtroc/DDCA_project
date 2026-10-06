#ifndef PTROCOS_VIDEO_PLAYER_H
#define PTROCOS_VIDEO_PLAYER_H
#include "video_decode.h"
int ptrocos_video_play(const struct media_source *source,struct media_work *work,
    void (*write)(void *,const char *),void *context,const volatile uint32_t *cancel);
int ptrocos_video_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel);
#endif

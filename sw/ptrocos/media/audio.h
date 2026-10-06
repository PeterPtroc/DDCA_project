#ifndef PTROCOS_AUDIO_H
#define PTROCOS_AUDIO_H
#include <stdint.h>
#define PTROCOS_AUDIO_BASE 0x4000f000U
struct ptrocos_audio {unsigned owned,started,manual_start;const volatile uint32_t *cancel;};
void ptrocos_audio_init(void);
int ptrocos_audio_begin(struct ptrocos_audio *a,uint32_t rate,const volatile uint32_t *cancel);
int ptrocos_audio_feed(struct ptrocos_audio *a,const uint16_t *samples,unsigned count);
int ptrocos_audio_end(struct ptrocos_audio *a);
void ptrocos_audio_abort(struct ptrocos_audio *a);
#ifdef PTROCOS_VIDEO
int ptrocos_audio_start(struct ptrocos_audio *a);
int ptrocos_audio_finish(struct ptrocos_audio *a);
int ptrocos_audio_query(const struct ptrocos_audio *a,uint32_t *played,uint32_t *free,unsigned *running);
#endif
int ptrocos_audio_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel);
#endif

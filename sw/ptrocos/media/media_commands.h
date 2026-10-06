#ifndef PTROCOS_MEDIA_COMMANDS_H
#define PTROCOS_MEDIA_COMMANDS_H
#include "ff.h"
#include <stdint.h>
// Called only with the storage command lock and cancellation source held.
FRESULT ptrocos_media_file(FIL *file,unsigned wav,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel);
#endif

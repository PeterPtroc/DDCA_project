#ifndef PTROCOS_STORAGE_COMMANDS_H
#define PTROCOS_STORAGE_COMMANDS_H
#include <stdint.h>
void ptrocos_storage_init(void);
// Returns zero only when argv[0] is not a storage command.
// String writer handles diagnostics; byte writer preserves NUL and UTF-8 data.
int ptrocos_storage_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void (*write_byte)(void *,uint8_t),void *context,volatile uint32_t *cancel);
#endif

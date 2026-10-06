#ifndef PTROCOS_STORAGE_COMMANDS_H
#define PTROCOS_STORAGE_COMMANDS_H
#include <stdint.h>
void ptrocos_storage_init(void);
// Returns zero only when argv[0] is not a storage command.
int ptrocos_storage_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,volatile uint32_t *cancel);
#endif

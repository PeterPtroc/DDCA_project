#include "elf/elf_runtime.h"
static int (*sink)(uint32_t,const void *,unsigned);
void elf_native_sink(int (*callback)(uint32_t,const void *,unsigned)) {sink=callback;}
int ptrocos_elf_memory_write(void *context,uint32_t address,const void *data,unsigned bytes)
{(void)context;return sink ? sink(address,data,bytes) : ELF_OUTPUT;}
void ptrocos_elf_progress(void *context) {(void)context;}

#ifndef PTROCOS_ELF_RUNTIME_H
#define PTROCOS_ELF_RUNTIME_H
#include "elf_decode.h"
void ptrocos_elf_init(void);
int ptrocos_elf_command(unsigned,char **,void (*)(void *,const char *),void *,volatile uint32_t *);
int ptrocos_elf_exception(uint32_t cause,uint32_t resume_pc);
int ptrocos_elf_memory_write(void *,uint32_t,const void *,unsigned);
void ptrocos_elf_progress(void *);
#endif

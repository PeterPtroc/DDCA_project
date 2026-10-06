#ifndef PTROCOS_ELF_DECODE_H
#define PTROCOS_ELF_DECODE_H
#include <stdint.h>
#define PTROCOS_APP_CODE_BASE 0x00010000U
#define PTROCOS_APP_CODE_END  0x00014000U
#define PTROCOS_APP_DATA_BASE 0x80800000U
#define PTROCOS_APP_DATA_END  0x808ff000U
#define PTROCOS_APP_STACK_END 0x80900000U
#define PTROCOS_ELF_SEGMENTS 8U
enum elf_result {ELF_OK,ELF_FORMAT,ELF_RANGE,ELF_ABI,ELF_IO,ELF_CANCEL,ELF_OUTPUT};
struct elf_source {
    uint32_t size;
    int (*read)(void *,uint32_t,void *,unsigned);
    int (*cancelled)(void *);
    void *context;
};
struct elf_segment {uint32_t offset,address,file_bytes,memory_bytes,flags;};
struct elf_image {
    uint32_t entry,count,file_bytes,memory_bytes,abi_version,loaded;
    struct elf_segment segments[PTROCOS_ELF_SEGMENTS];
};
struct elf_sink {
    int (*write)(void *,uint32_t,const void *,unsigned);
    void (*progress)(void *);
    void *context;
};
// inspect never writes a destination. load repeats complete inspection, then
// copies all segments and zeros BSS with a fixed 256-byte scratch buffer.
// Only loaded=1 permits execution; cancellation/any error leaves loaded=0.
int ptrocos_elf_inspect(const struct elf_source *,struct elf_image *);
int ptrocos_elf_load(const struct elf_source *,const struct elf_sink *,struct elf_image *);
#endif

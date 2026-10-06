#ifndef PTROCOS_APP_API_H
#define PTROCOS_APP_API_H
#include <stdint.h>
// Version 1: trusted RV32IM ILP32 M-mode calls. Keep gp/tp and CSRs unchanged.
// Use the supplied linker/CRT, 16-byte aligned 4 KiB stack and no gp relaxation.
struct ptrocos_app_api {
    uint32_t version;
    int (*write)(const char *,unsigned);
    void (*yield)(void);
    int (*cancelled)(void);
};
typedef int (*ptrocos_app_entry)(const struct ptrocos_app_api *,int,const char *const *);
#endif

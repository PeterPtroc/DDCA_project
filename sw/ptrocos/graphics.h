#ifndef PTROCOS_GRAPHICS_H
#define PTROCOS_GRAPHICS_H
#include <stdint.h>
#define PTROCOS_GFX_WIDTH 640U
#define PTROCOS_GFX_HEIGHT 480U
#define PTROCOS_GFX_STRIDE (PTROCOS_GFX_WIDTH*2U)
#define PTROCOS_GFX_BASE 0x4000e000U
#define PTROCOS_GFX_BUFFER_A 0x81000000U
#define PTROCOS_GFX_BUFFER_B 0x81100000U
enum { GFX_OK=0,GFX_CANCELLED=1,GFX_TIMEOUT=2,GFX_INVALID=3 };
struct ptrocos_canvas {uint32_t base;unsigned owned;};
void ptrocos_graphics_init(void);
int ptrocos_graphics_begin(struct ptrocos_canvas *canvas,const volatile uint32_t *cancel);
int ptrocos_graphics_row(struct ptrocos_canvas *canvas,unsigned row,const uint32_t *pixels,
    const volatile uint32_t *cancel);
int ptrocos_graphics_present(struct ptrocos_canvas *canvas);
void ptrocos_graphics_abort(struct ptrocos_canvas *canvas);
int ptrocos_graphics_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel);
#endif

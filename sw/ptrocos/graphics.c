#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "board.h"
#include "shell.h"
#include "graphics.h"
#include <string.h>

static SemaphoreHandle_t graphics_lock;
// Both TTY sessions serialize the complete back-buffer drawing operation.
static uint32_t scanline[PTROCOS_GFX_WIDTH/2];
static uint32_t reg(unsigned offset) {return PTROCOS_MMIO32(PTROCOS_GFX_BASE+offset);}
static void put(unsigned offset,uint32_t value) {PTROCOS_MMIO32(PTROCOS_GFX_BASE+offset)=value;}
static int cancelled(const volatile uint32_t *cancel) {return cancel && *cancel;}
static int lock(const volatile uint32_t *cancel)
{
    while(xSemaphoreTake(graphics_lock,1)!=pdTRUE) if(cancelled(cancel)) return GFX_CANCELLED;
    return GFX_OK;
}
static int wait_commit(void)
{
    TickType_t begin=xTaskGetTickCount();
    while(reg(12)&2U) {
        if(xTaskGetTickCount()-begin>=1000) return GFX_TIMEOUT;
        vTaskDelay(1);
    }
    return GFX_OK;
}
void ptrocos_graphics_init(void)
{
    graphics_lock=xSemaphoreCreateMutex();configASSERT(graphics_lock!=NULL);
    configASSERT(reg(44)==((PTROCOS_GFX_HEIGHT<<16)|PTROCOS_GFX_WIDTH) && reg(48)==0x565);
}
int ptrocos_graphics_begin(struct ptrocos_canvas *canvas,const volatile uint32_t *cancel)
{
    canvas->owned=0;
    int result=lock(cancel);if(result) return result;
    result=wait_commit();
    if(!result && cancelled(cancel)) result=GFX_CANCELLED;
    if(result) {(void)xSemaphoreGive(graphics_lock);return result;}
    canvas->base=reg(16)==PTROCOS_GFX_BUFFER_A ? PTROCOS_GFX_BUFFER_B : PTROCOS_GFX_BUFFER_A;
    canvas->owned=1;return GFX_OK;
}
int ptrocos_graphics_row(struct ptrocos_canvas *canvas,unsigned row,const uint32_t *pixels,
    const volatile uint32_t *cancel)
{
    if(!canvas->owned || row>=PTROCOS_GFX_HEIGHT) return GFX_INVALID;
    if(cancelled(cancel)) return GFX_CANCELLED;
    volatile uint32_t *destination=(volatile uint32_t *)(uintptr_t)(canvas->base+row*PTROCOS_GFX_STRIDE);
    for(unsigned i=0;i<PTROCOS_GFX_WIDTH/2;i++) destination[i]=pixels[i];
    return GFX_OK;
}
void ptrocos_graphics_abort(struct ptrocos_canvas *canvas)
{
    if(canvas->owned) {canvas->owned=0;(void)xSemaphoreGive(graphics_lock);}
}
int ptrocos_graphics_present(struct ptrocos_canvas *canvas)
{
    if(!canvas->owned) return GFX_INVALID;
    // Stores have reached DDR before the register mailbox publishes this buffer.
    __asm__ volatile("fence iorw,iorw" ::: "memory");
    put(0,canvas->base);put(4,PTROCOS_GFX_STRIDE);put(8,3);
    // A queued flip must drain even if Ctrl+C arrives. A timeout leaves pending
    // visible in hardware; the next begin waits before selecting a back buffer.
    int result=wait_commit();
    if(!result && (reg(16)!=canvas->base || !(reg(12)&1U))) result=GFX_INVALID;
    ptrocos_graphics_abort(canvas);return result;
}
static uint16_t color(unsigned pattern,unsigned x,unsigned y)
{
    static const uint16_t bars[8]={0xffff,0xffe0,0x07ff,0x07e0,0xf81f,0xf800,0x001f,0};
    if(!pattern) return bars[x/80];
    return (uint16_t)(((x>>4)<<11)|((y>>3)<<5)|((x^y)>>4&31U));
}
static int pattern(unsigned number,const volatile uint32_t *cancel)
{
    struct ptrocos_canvas canvas;
    int result=ptrocos_graphics_begin(&canvas,cancel);if(result) return result;
    for(unsigned y=0;y<PTROCOS_GFX_HEIGHT && !result;y++) {
        for(unsigned x=0;x<PTROCOS_GFX_WIDTH;x+=2)
            scanline[x/2]=(uint32_t)color(number,x,y)|((uint32_t)color(number,x+1,y)<<16);
        result=ptrocos_graphics_row(&canvas,y,scanline,cancel);
        // Keep both input and the other terminal responsive while painting.
        if(!(y&7U)) vTaskDelay(1);
    }
    if(!result && cancelled(cancel)) result=GFX_CANCELLED;
    if(!result) return ptrocos_graphics_present(&canvas);
    ptrocos_graphics_abort(&canvas);return result;
}
static void number(void (*write)(void *,const char *),void *context,const char *name,uint32_t value)
{
    char text[11];unsigned n=0;
    do {text[n++]=(char)('0'+value%10);value/=10;} while(value);
    for(unsigned i=0;i<n/2;i++) {char t=text[i];text[i]=text[n-1-i];text[n-1-i]=t;}
    text[n]=0;write(context,name);write(context,text);
}
int ptrocos_graphics_command(unsigned argc,char **argv,void (*write)(void *,const char *),
    void *context,const volatile uint32_t *cancel)
{
    if(strcmp(argv[0],"gfx")) return 0;
    int result=GFX_OK;
    uint32_t choice;
    if(argc==2 && !strcmp(argv[1],"info")) {
        write(context,"gfx 640x480 RGB565 stride=1280");
        number(write,context," status=",reg(12));number(write,context," front=",reg(16));
        number(write,context," frames=",reg(24));number(write,context," swaps=",reg(28));
        number(write,context," underruns=",reg(32));number(write,context," beats=",reg(36));
        number(write,context," errors=",reg(40));write(context,"\r\n");
    } else if(argc==3 && !strcmp(argv[1],"pattern") && shell_u32(argv[2],&choice) && choice<=1) {
        write(context,"gfx drawing; Ctrl+C cancels\r\n");result=pattern(choice,cancel);
        if(!result) {number(write,context,"gfx pattern=",choice);write(context," displayed\r\n");}
    } else if(argc==2 && (!strcmp(argv[1],"off") || !strcmp(argv[1],"clear"))) {
        result=lock(cancel);
        if(!result) {
            result=wait_commit();
            if(!result && cancelled(cancel)) result=GFX_CANCELLED;
            if(!result) {put(8,!strcmp(argv[1],"off") ? 1 : 4);result=wait_commit();}
            (void)xSemaphoreGive(graphics_lock);
        }
        if(!result) write(context,!strcmp(argv[1],"off") ? "gfx text mode\r\n" : "gfx sticky errors cleared\r\n");
    } else write(context,"usage: gfx info | pattern 0..1 | off | clear\r\n");
    if(result==GFX_TIMEOUT) write(context,"gfx commit timeout; check gfx info before retry\r\n");
    else if(result==GFX_INVALID) write(context,"gfx configuration error\r\n");
    return 1;
}

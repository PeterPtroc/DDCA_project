#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "board.h"
#include "keyboard.h"
#include "text_console.h"
#include "tty.h"
#include "shell.h"
#include <string.h>
#ifdef PTROCOS_MEDIA
#include "media/audio.h"
#endif
#ifdef PTROCOS_VIDEO
#include "media/video_player.h"
#endif
#ifdef PTROCOS_GRAPHICS
#include "graphics.h"
#endif
#ifdef PTROCOS_STORAGE
#include "storage/storage_commands.h"
#endif

struct session {
    struct tty tty;
    QueueHandle_t input;
    unsigned index;
    volatile uint32_t active,abort,dropped;
    unsigned discarding;
};
static struct session sessions[2];
static SemaphoreHandle_t dma_lock;
static volatile uint32_t heartbeat,io_polls,ps2_recoveries,uart_recoveries,seen;
static void mark_seen(unsigned bit)
{
    taskENTER_CRITICAL();seen|=bit;taskEXIT_CRITICAL();
}
static void panic(uint32_t code)
{
    __asm__ volatile("csrci mstatus,8");
    PTROCOS_MMIO32(0x4000000cU)=0xbad50000U|code;
    ptrocos_uart_puts("PTROCOS PANIC ");ptrocos_uart_hex(code);ptrocos_uart_putc('\n');
    for(;;) { }
}
void vAssertCalled(const char *file,int line) {(void)file;panic(0x100U|(unsigned)line);}
void vApplicationMallocFailedHook(void) {panic(2);}
void vApplicationStackOverflowHook(TaskHandle_t task,char *name) {(void)task;(void)name;panic(3);}
void freertos_risc_v_application_exception_handler(uint32_t cause,uint32_t pc) {(void)pc;panic(0x200U|cause);}
void freertos_risc_v_application_interrupt_handler(uint32_t cause,uint32_t pc) {(void)pc;panic(0x300U|cause);}
void vApplicationIdleHook(void)
{
    if(seen==15 && heartbeat>=2) PTROCOS_MMIO32(0x4000000cU)=0x600d7005U;
}
static int same(const char *a,const char *b)
{
    while(*a && *a==*b) {++a;++b;}
    return *a==*b;
}
static void putc_session(struct session *s,char ch)
{
    if(s->index) ptrocos_text_putc(ch);
    else ptrocos_uart_putc(ch);
}
static void output(void *context,const char *text)
{
    struct session *s=context;
    while(*text && !(s->active && s->abort)) putc_session(s,*text++);
}
#ifdef PTROCOS_STORAGE
static void output_byte(void *context,uint8_t value)
{
    struct session *s=context;
    if(!(s->active && s->abort)) putc_session(s,(char)value);
}
#endif
static void decimal(struct session *s,uint32_t number)
{
    char digits[11];unsigned count=0;
    do {digits[count++]=(char)('0'+number%10);number/=10;} while(number);
    while(count) putc_session(s,digits[--count]);
}
static void hex(struct session *s,uint32_t number)
{
    static const char digits[]="0123456789abcdef";
    for(int shift=28;shift>=0;shift-=4) putc_session(s,digits[(number>>shift)&15]);
}
static void field(struct session *s,const char *name,uint32_t value)
{
    output(s,name);decimal(s,value);
}
static void clear(void *context)
{
    struct session *s=context;
    if(s->index) ptrocos_text_clear();else output(s,"\033[2J\033[H");
}
static void redraw(void *context,const char *line,unsigned length,unsigned caret)
{
    struct session *s=context;
    if(s->index) ptrocos_text_redraw(TTY_PROMPT,line,length,caret);
    else {
        output(s,"\r\033[2K" TTY_PROMPT);output(s,line);
        if(length>caret) {output(s,"\033[");decimal(s,length-caret);putc_session(s,'D');}
    }
}
static void dma_test(struct session *s)
{
    while(xSemaphoreTake(dma_lock,1)!=pdTRUE) if(s->abort) return;
    volatile uint32_t *const dma=(volatile uint32_t *)(uintptr_t)PTROCOS_DMA_BASE;
    volatile uint32_t *const source=(volatile uint32_t *)(uintptr_t)(PTROCOS_DDR_BASE+0x1000U);
    volatile uint32_t *const destination=(volatile uint32_t *)(uintptr_t)(PTROCOS_DDR_BASE+0x2000U);
    for(unsigned i=0;i<256;i++) {source[i]=(i*0x9e3779b9U)^0xa55a1357U;destination[i]=0;}
    dma[0]=(uint32_t)(uintptr_t)source;dma[1]=(uint32_t)(uintptr_t)destination;dma[2]=256;
    __asm__ volatile("fence iorw,iorw" ::: "memory");dma[3]=1;
    TickType_t started=xTaskGetTickCount();
    while(dma[4]&1U) {
        if(s->abort) dma[3]=2; // Drain the outstanding word before releasing ownership.
        if(xTaskGetTickCount()-started>1000) panic(4);
        vTaskDelay(1);
    }
    if(!s->abort) {
        if((dma[4]&7U)!=2U || dma[5]!=256) panic(5);
        for(unsigned i=0;i<256;i++) if(destination[i]!=((i*0x9e3779b9U)^0xa55a1357U)) panic(6);
        uint16_t crc=ptrocos_crc16(0xffff,destination,1024);
        if(crc!=0xf364) panic(7);
        output(s,"DDR DMA PASS words=256 crc=");hex(s,crc);output(s,"\r\n");
    }
    (void)xSemaphoreGive(dma_lock);
}
static void command(void *context,const char *input)
{
    struct session *s=context;
    char line[TTY_LINE_CAP],*argv[SHELL_ARGS];unsigned argc;
    memcpy(line,input,strlen(input)+1);
    int parsed=shell_parse(line,argv,&argc);
    if(parsed!=SHELL_OK) {output(s,"syntax error: quotes, escape or argument limit\r\n");return;}
    if(!argc) return;
    s->abort=0;s->active=1;
    const char *name=argv[0];
    if(same(name,"echo")) {
        for(unsigned i=1;i<argc;i++) {if(i>1) output(s," ");output(s,argv[i]);}
        output(s,"\r\n");
    } else if(same(name,"sleep")) {
        uint32_t milliseconds;
        if(argc!=2 || !shell_u32(argv[1],&milliseconds) || milliseconds>60000)
            output(s,"usage: sleep 0..60000\r\n");
        else {
            output(s,"sleeping; Ctrl+C cancels\r\n");
            TickType_t begin=xTaskGetTickCount();
            while(!s->abort && xTaskGetTickCount()-begin<milliseconds) vTaskDelay(1);
            if(!s->abort) output(s,"sleep done\r\n");
        }
    }
#ifdef PTROCOS_STORAGE
    else if(ptrocos_storage_command(argc,argv,output,output_byte,s,&s->abort)) { }
#endif
#ifdef PTROCOS_GRAPHICS
    else if(ptrocos_graphics_command(argc,argv,output,s,&s->abort)) { }
#endif
    #ifdef PTROCOS_MEDIA
    else if(ptrocos_audio_command(argc,argv,output,s,&s->abort)) { }
#endif
#ifdef PTROCOS_VIDEO
    else if(ptrocos_video_command(argc,argv,output,s,&s->abort)) { }
#endif
    else if(argc!=1) output(s,"unexpected arguments\r\n");
    else if(same(name,"help")) {
        for(unsigned i=0;i<shell_command_count && !s->abort;i++) {
            output(s,shell_commands[i]);output(s,i+1==shell_command_count ? "\r\n" : " ");
        }
        output(s,"arrows/Home/End/Delete edit; Up/Down history; Tab completes\r\nCtrl+U/K/W/L edit/clear; Ctrl+C cancels\r\n");
    } else if(same(name,"clear")) clear(s);
    else if(same(name,"uname")) output(s,"PtrocOS RV32IM / FreeRTOS 11.3.1 / Nexys A7-100T\r\n");
    else if(same(name,"uptime")) {
        field(s,"ticks=",xTaskGetTickCount());field(s," heartbeat=",heartbeat);
        field(s," io_polls=",io_polls);field(s," input_dropped=",s->dropped);output(s,"\r\n");
    } else if(same(name,"mem")) {
        field(s,"heap_free=",xPortGetFreeHeapSize());field(s," heap_min=",xPortGetMinimumEverFreeHeapSize());
        output(s," bram=65536 ddr=134217728\r\n");
    } else if(same(name,"video")) {
        field(s,"frames=",PTROCOS_MMIO32(0x4000b008U));field(s," cursor=",PTROCOS_MMIO32(0x4000b004U));
        output(s," mode=640x480 text=80x30 pixel_hz=25200000\r\n");
    } else if(same(name,"kbd")) {
        field(s,"status=",PTROCOS_MMIO32(0x4000c000U));field(s," received=",PTROCOS_MMIO32(0x4000c008U));
        field(s," errors=",PTROCOS_MMIO32(0x4000c00cU));field(s," timeouts=",PTROCOS_MMIO32(0x4000c010U));
        field(s," overflow=",PTROCOS_MMIO32(0x4000c014U));field(s," edges=",PTROCOS_MMIO32(0x4000c01cU));
        field(s," recoveries=",ps2_recoveries);output(s,"\r\n");
    } else if(same(name,"tasks")) {
        TaskStatus_t states[5];
        unsigned count=uxTaskGetSystemState(states,5,NULL);
        output(s,"name priority state stack_free_words\r\n");
        for(unsigned i=0;i<count && !s->abort;i++) {
            output(s,states[i].pcTaskName);field(s," ",states[i].uxCurrentPriority);
            field(s," ",states[i].eCurrentState);field(s," ",states[i].usStackHighWaterMark);output(s,"\r\n");
        }
    } else if(same(name,"ddrtest")) dma_test(s);
    else output(s,"unknown command; use help\r\n");
    s->active=0;
    if(s->abort) output(s,"^C cancelled\r\n");
}
static void input_lost(struct session *s)
{
    ++s->dropped;s->discarding=1;s->abort=1;
    (void)xQueueReset(s->input);
    int16_t event=TTY_INPUT_LOST;
    configASSERT(xQueueSend(s->input,&event,0)==pdPASS);
}
static void deliver(struct session *s,int key)
{
    if(s->discarding) {
        if(key=='\n' || key=='\r' || key==3) s->discarding=0;
        return;
    }
    if(key==3 && s->active) {s->abort=1;return;}
    int16_t event=(int16_t)key;
    if(xQueueSend(s->input,&event,0)!=pdPASS) {
        input_lost(s);
        if(key=='\n' || key=='\r' || key==3) s->discarding=0;
    }
}
static void input_task(void *argument)
{
    (void)argument;
    struct ptrocos_keyboard keyboard;ptrocos_keyboard_reset(&keyboard);
    for(;;) {
        mark_seen(1);++io_polls;
        if(PTROCOS_MMIO32(0x40001004U)&4U) {
            ++uart_recoveries;input_lost(&sessions[0]);
            while(ptrocos_uart_getc()>=0) { }
            PTROCOS_MMIO32(0x40001004U)=4;
        }
        for(unsigned i=0;i<32;i++) {
            int ch=ptrocos_uart_getc();if(ch<0) break;deliver(&sessions[0],ch);
        }
        uint32_t flags=PTROCOS_MMIO32(0x4000c000U);
        if(flags&14) {
            ++ps2_recoveries;PTROCOS_MMIO32(0x4000c018U)=3;
            ptrocos_keyboard_reset(&keyboard);input_lost(&sessions[1]);
        } else for(unsigned i=0;i<32 && (PTROCOS_MMIO32(0x4000c000U)&1U);i++) {
            int key=ptrocos_keyboard_decode(&keyboard,(uint8_t)PTROCOS_MMIO32(0x4000c004U));
            if(key>=0) deliver(&sessions[1],key);
        }
        vTaskDelay(1);
    }
}
static void terminal_task(void *argument)
{
    struct session *s=argument;
    mark_seen(s->index ? 4U : 2U);
    output(s,s->index ? "PtrocOS VGA/PS2 terminal\r\n" : "PTROCOS SHELL READY\r\n");
    struct tty_callbacks callbacks={output,redraw,clear,command,s};
    tty_init(&s->tty,&callbacks);
    for(;;) {
        int16_t key;
        TickType_t wait=s->tty.escape ? 100 : portMAX_DELAY;
        if(xQueueReceive(s->input,&key,wait)!=pdPASS) tty_uart_timeout(&s->tty);
        else if(s->index || key==TTY_INPUT_LOST) tty_key(&s->tty,key);
        else tty_uart_byte(&s->tty,(uint8_t)key);
    }
}
static void heartbeat_task(void *argument)
{
    (void)argument;TickType_t next=xTaskGetTickCount();
    for(;;) {
        mark_seen(8);++heartbeat;PTROCOS_MMIO32(0x40000000U)=heartbeat&1U;
        (void)xTaskDelayUntil(&next,10);
    }
}
int main(void)
{
    uint32_t misa;__asm__ volatile("csrr %0,misa":"=r"(misa));
    if(misa!=0x40001100U || PTROCOS_MMIO32(0x4000b00cU)!=0x001e0050U) panic(1);
    ptrocos_text_clear();PTROCOS_MMIO32(0x4000c018U)=3;
#ifdef PTROCOS_GRAPHICS
    ptrocos_graphics_init();
#ifdef PTROCOS_MEDIA
    ptrocos_audio_init();
#endif
#endif
    #ifdef PTROCOS_STORAGE
    ptrocos_storage_init();
    const unsigned terminal_stack=1536;
#else
    const unsigned terminal_stack=768;
#endif
    dma_lock=xSemaphoreCreateMutex();configASSERT(dma_lock!=NULL);
    for(unsigned i=0;i<2;i++) {
        sessions[i].index=i;sessions[i].input=xQueueCreate(128,sizeof(int16_t));
        configASSERT(sessions[i].input!=NULL);
    }
    configASSERT(xTaskCreate(input_task,"input",320,NULL,3,NULL)==pdPASS);
    configASSERT(xTaskCreate(terminal_task,"uart-tty",terminal_stack,&sessions[0],2,NULL)==pdPASS);
    configASSERT(xTaskCreate(terminal_task,"vga-tty",terminal_stack,&sessions[1],2,NULL)==pdPASS);
    configASSERT(xTaskCreate(heartbeat_task,"heartbeat",192,NULL,4,NULL)==pdPASS);
    vTaskStartScheduler();panic(8);return 0;
}

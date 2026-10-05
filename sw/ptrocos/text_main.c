#include "board.h"
#include "keyboard.h"
#include "text_console.h"
static struct ptrocos_keyboard keyboard;
static volatile uint32_t timer_ticks;
static void fail(uint32_t code)
{
    __asm__ volatile ("csrci mstatus,8");
    ptrocos_uart_puts("TEXT PS2 FAIL ");ptrocos_uart_hex(code);ptrocos_uart_putc('\n');
    PTROCOS_MMIO32(0x4000000cU)=0xbad10000U|code;
    for(;;) { }
}
void ptrocos_trap_handler(uint32_t cause,uint32_t pc,uint32_t value)
{
    (void)pc;(void)value;
    if(cause==0x80000007U) {++timer_ticks;ptrocos_timer_schedule(PTROCOS_CPU_HZ/1000U);}
    else fail(0x100U|cause);
}
static void selftest(void)
{
    volatile uint32_t *const cells=(volatile uint32_t *)(uintptr_t)0x40010000U;
    PTROCOS_MMIO32(0x4000b000U)=0;
    for(unsigned i=0;i<2400;i++) cells[i]=((i&255U)<<8)|(32U+i%95U);
    for(unsigned i=0;i<2400;i++) if(cells[i]!=(((i&255U)<<8)|(32U+i%95U))) fail(1);
    volatile uint8_t *bytes=(volatile uint8_t *)&cells[2399];
    bytes[0]='A';bytes[1]=0x1e;
    if(cells[2399]!=0x1e41) fail(2);
    cells[2400]=0xdead;
    if(cells[2400]!=0 || cells[0]!=0x20) fail(3);
    if(PTROCOS_MMIO32(0x4000b00cU)!=0x001e0050U || PTROCOS_MMIO32(0x4000b014U)!=25200000U) fail(4);
    PTROCOS_MMIO32(0x4000b004U)=2399;
    if(PTROCOS_MMIO32(0x4000b004U)!=2399) fail(5);
    uint32_t frame=PTROCOS_MMIO32(0x4000b008U);
    uint64_t deadline=ptrocos_mtime()+PTROCOS_CPU_HZ/20U;
    while(PTROCOS_MMIO32(0x4000b008U)==frame) if(ptrocos_mtime()>deadline) fail(6);
    if(timer_ticks==0) fail(7);
    // DDR and DMA remain live while the independent pixel engine scans text.
    volatile uint32_t *const dma=(volatile uint32_t *)(uintptr_t)PTROCOS_DMA_BASE;
    volatile uint32_t *const source=(volatile uint32_t *)(uintptr_t)(PTROCOS_DDR_BASE+0x1000U);
    volatile uint32_t *const destination=(volatile uint32_t *)(uintptr_t)(PTROCOS_DDR_BASE+0x2000U);
    for(unsigned i=0;i<16;i++) {source[i]=i*0x13579bU+0xabcdefU;destination[i]=0;}
    dma[0]=(uint32_t)(uintptr_t)source;dma[1]=(uint32_t)(uintptr_t)destination;dma[2]=16;dma[3]=1;
    deadline=ptrocos_mtime()+PTROCOS_CPU_HZ/20U;
    while(dma[4]&1U) if(ptrocos_mtime()>deadline) fail(8);
    if((dma[4]&7U)!=2U || dma[5]!=16U) fail(9);
    for(unsigned i=0;i<16;i++) if(destination[i]!=source[i]) fail(10);
    ptrocos_text_clear();
    ptrocos_text_puts("PtrocOS  RV32IM + DDR2 + DMA\nVGA 640x480  80x30 text  PS/2 set 2\n\nKeyboard echo test; UART 'v' reports status.\n");
    PTROCOS_MMIO32(0x4000c018U)=3;ptrocos_keyboard_reset(&keyboard);
    ptrocos_uart_puts("TEXT PS2 READY\n");PTROCOS_MMIO32(0x4000000cU)=0x600d7004U;
}
static void status(void)
{
    ptrocos_uart_puts("VIDEO frames=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000b008U));
    ptrocos_uart_puts(" cursor=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000b004U));
    ptrocos_uart_puts(" ticks=");ptrocos_uart_hex(timer_ticks);
    ptrocos_uart_puts(" PS2 status=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000c000U));
    ptrocos_uart_puts(" rx=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000c008U));
    ptrocos_uart_puts(" errors=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000c00cU));
    ptrocos_uart_puts(" timeout=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000c010U));
    ptrocos_uart_puts(" overflow=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000c014U));
    ptrocos_uart_puts(" clock_edges=");ptrocos_uart_hex(PTROCOS_MMIO32(0x4000c01cU));
    ptrocos_uart_putc('\n');
}
int main(void)
{
    ptrocos_timer_schedule(PTROCOS_CPU_HZ/1000U);
    __asm__ volatile ("csrw mie,%0" :: "r"(1U<<7));__asm__ volatile ("csrsi mstatus,8");
    selftest();
    for(;;) {
        if(ptrocos_uart_getc()=='v') status();
        uint32_t flags=PTROCOS_MMIO32(0x4000c000U);
        if(flags&14U) {
            // Loss of a break/prefix could otherwise leave a modifier stuck.
            PTROCOS_MMIO32(0x4000c018U)=3;ptrocos_keyboard_reset(&keyboard);
            ptrocos_uart_puts("PS2 RECOVER\n");
        } else if(flags&1U) {
            int key=ptrocos_keyboard_decode(&keyboard,(uint8_t)PTROCOS_MMIO32(0x4000c004U));
            if(key>=0) {
                ptrocos_uart_puts("KEY ");ptrocos_uart_hex((uint32_t)key);ptrocos_uart_putc('\n');
                if(key<128) ptrocos_text_putc((char)key);
            }
        }
    }
}

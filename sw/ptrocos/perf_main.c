#include "board.h"
#include "perf_data.h"
static volatile uint32_t bram[256];
static volatile uint32_t *const ddr=(volatile uint32_t *)(uintptr_t)0x80000000U;
static volatile uint32_t *const dma=(volatile uint32_t *)(uintptr_t)PTROCOS_DMA_BASE;
static uint32_t begin_cycles,begin_retired;
static uint32_t cycles(void) {uint32_t n;__asm__ volatile("csrr %0,mcycle":"=r"(n)::"memory");return n;}
static uint32_t retired(void) {uint32_t n;__asm__ volatile("csrr %0,minstret":"=r"(n)::"memory");return n;}
static void fail(uint32_t code)
{PTROCOS_MMIO32(0x4000000cU)=0xbad60000U|code;for(;;) {}}
void ptrocos_trap_handler(uint32_t cause,uint32_t pc,uint32_t value)
{(void)pc;(void)value;fail(0x100U|cause);}
static void begin(unsigned phase)
{PTROCOS_MMIO32(0x4000000cU)=0xcace0000U|phase;begin_retired=retired();begin_cycles=cycles();}
static void end(unsigned phase,uint32_t sum,uint32_t expected)
{
    uint32_t elapsed=cycles()-begin_cycles, instructions=retired()-begin_retired;
    PTROCOS_MMIO32(0x4000000cU)=0xcafe0000U|phase;
    if(sum!=expected) fail(phase);
    ptrocos_uart_puts("PERF case=");ptrocos_uart_hex(phase);
    ptrocos_uart_puts(" cycles=");ptrocos_uart_hex(elapsed);
    ptrocos_uart_puts(" retired=");ptrocos_uart_hex(instructions);
    ptrocos_uart_puts(" checksum=");ptrocos_uart_hex(sum);ptrocos_uart_putc('\n');
}
__attribute__((noinline)) static uint32_t read_sum(const volatile uint32_t *p,unsigned words,unsigned repeats)
{uint32_t sum=0;for(unsigned r=0;r<repeats;r++) for(unsigned i=0;i<words;i++) sum+=p[i];return sum;}
int main(void)
{
    for(unsigned i=0;i<256;i++) bram[i]=17*i+3;
    for(unsigned i=0;i<1024;i++) ddr[i]=17*i+3;
    begin(0);__asm__ volatile("nop":::"memory");end(0,0,0);
    uint32_t sum=0;
    begin(1);for(unsigned i=0;i<1024;i++) __asm__ volatile("add %0,%0,%1":"+r"(sum):"r"(i));end(1,sum,523776);
    begin(2);sum=read_sum(perf_rom,256,4);end(2,sum,2222592);
    begin(3);sum=read_sum(bram,256,4);end(3,sum,2222592);
    begin(4);sum=read_sum(ddr,256,4);end(4,sum,2222592);
    begin(5);sum=read_sum(ddr,1024,1);end(5,sum,8907264);
    begin(6);for(unsigned i=0;i<256;i++) ddr[i]=17*i+3;end(6,256,256);
    for(unsigned i=0;i<256;i++) ddr[i]=(i+37)&255U;
    unsigned index=0;sum=0;
    begin(7);for(unsigned i=0;i<1024;i++) {index=ddr[index];sum+=index;}end(7,sum,130560);
    for(unsigned i=0;i<256;i++) ddr[i]=17*i+3;
    dma[0]=0x80000000U;dma[1]=0x80010000U;dma[2]=256;
    begin(8);dma[3]=1;sum=read_sum(ddr,256,4);while(dma[4]&1U) {}end(8,sum,2222592);
    if((dma[4]&7U)!=2 || dma[5]!=256) fail(0x200);
    for(unsigned i=0;i<256;i++) if(PTROCOS_MMIO32(0x80010000U+i*4)!=17*i+3) fail(0x201);
    ptrocos_uart_puts("PTROCOS PERF FIRMWARE PASS\n");
    PTROCOS_MMIO32(0x4000000cU)=0x600d600dU;
    for(;;) {}
}

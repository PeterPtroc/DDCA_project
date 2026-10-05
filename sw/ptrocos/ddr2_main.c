#include "board.h"
static volatile uint32_t timer_ticks, expected_fault, fault_count;
static volatile uint32_t *const dma=(volatile uint32_t *)(uintptr_t)PTROCOS_DMA_BASE;

static void fail(uint32_t code)
{
    __asm__ volatile ("csrci mstatus,8");
    ptrocos_uart_puts("DDR2 DMA FAIL ");ptrocos_uart_hex(code);ptrocos_uart_putc('\n');
    PTROCOS_MMIO32(0x4000000cU)=0xbad00000U|code;
    for (;;) { }
}
void ptrocos_trap_handler(uint32_t cause,uint32_t pc,uint32_t value)
{
    if (cause==0x80000007U) {
        ++timer_ticks;
        ptrocos_timer_schedule(PTROCOS_CPU_HZ/1000U);
    } else if (expected_fault==cause && (cause==5U || cause==7U) && value==0x88000000U) {
        ++fault_count;expected_fault=0;
        __asm__ volatile ("csrw mepc,%0" :: "r"(pc+4U));
    } else fail(0x100U|cause);
}
static uint32_t pattern(uint32_t index)
{
    return (index*0x9e3779b9U)^0xa55a1357U;
}
static void address_test(void)
{
    volatile uint32_t *memory=(volatile uint32_t *)(uintptr_t)PTROCOS_DDR_BASE;
    memory[0]=pattern(0);
    for (uint32_t bit=0;bit<25;bit++) memory[1U<<bit]=pattern(1U<<bit);
    memory[(PTROCOS_DDR_BYTES/4U)-1U]=pattern((PTROCOS_DDR_BYTES/4U)-1U);
    __asm__ volatile ("fence iorw,iorw" ::: "memory");
    if (memory[0]!=pattern(0)) fail(1);
    for (uint32_t bit=0;bit<25;bit++) if (memory[1U<<bit]!=pattern(1U<<bit)) fail(2U+bit);
    if (memory[(PTROCOS_DDR_BYTES/4U)-1U]!=pattern((PTROCOS_DDR_BYTES/4U)-1U)) fail(27);
}
static void lane_test(void)
{
    volatile uint32_t *word=(volatile uint32_t *)(uintptr_t)(PTROCOS_DDR_BASE+0x400U);
    volatile uint8_t *bytes=(volatile uint8_t *)word;
    volatile uint16_t *halves=(volatile uint16_t *)word;
    word[0]=0x11223344U;word[1]=0x55667788U;
    bytes[1]=0xabU;halves[1]=0xcdefU;
    if (word[0]!=0xcdefab44U || word[1]!=0x55667788U) fail(32);
    if (*(volatile int8_t *)&bytes[1]!=-85 || *(volatile int16_t *)&halves[1]!=-12817) fail(33);
    if (bytes[1]!=0xabU || halves[1]!=0xcdefU) fail(34);
}
static void access_fault_test(void)
{
    uint32_t result=0x1234U;
    const uint32_t address=0x88000000U;
    uint32_t before=fault_count;
    expected_fault=5;
    __asm__ volatile ("lw %0,0(%1)" : "+r"(result) : "r"(address) : "memory");
    if (expected_fault!=0 || fault_count!=before+1U || result!=0x1234U) fail(40);
    expected_fault=7;
    __asm__ volatile ("sw %0,0(%1)" :: "r"(result),"r"(address) : "memory");
    if (expected_fault!=0 || fault_count!=before+2U) fail(41);
}
static void dma_test(void)
{
    volatile uint32_t *source=(volatile uint32_t *)(uintptr_t)(PTROCOS_DDR_BASE+0x1000U);
    volatile uint32_t *destination=(volatile uint32_t *)(uintptr_t)(PTROCOS_DDR_BASE+0x2000U);
    for (uint32_t i=0;i<256;i++) {source[i]=pattern(i);destination[i]=0;}
    dma[0]=(uint32_t)(uintptr_t)source;dma[1]=(uint32_t)(uintptr_t)destination;dma[2]=256;
    __asm__ volatile ("fence iorw,iorw" ::: "memory");
    dma[3]=1;
    // Make the first timer expiration land inside the copy, so the diagnostic
    // exercises interrupt entry while DMA owns outstanding DDR transactions.
    ptrocos_timer_schedule(PTROCOS_CPU_HZ/10000U);
    uint64_t deadline=ptrocos_mtime()+PTROCOS_CPU_HZ;
    uint32_t poll=0;
    while (dma[4]&1U) {
        // Deliberately contend with DMA, while preserving its source data.
        if (source[poll&255U]!=pattern(poll&255U)) fail(50);
        ++poll;
        if (ptrocos_mtime()>deadline) fail(51);
    }
    if ((dma[4]&7U)!=2U || dma[5]!=256U) fail(52);
    for (uint32_t i=0;i<256;i++) if (destination[i]!=pattern(i)) fail(53);
    uint16_t source_crc=ptrocos_crc16(0xffffU,source,1024);
    uint16_t destination_crc=ptrocos_crc16(0xffffU,destination,1024);
    if (source_crc!=destination_crc) fail(54);
    ptrocos_uart_puts("DMA CRC ");ptrocos_uart_hex(destination_crc);ptrocos_uart_putc('\n');
    dma[0]=PTROCOS_DDR_BASE;dma[1]=0x87fffffcU;dma[2]=2;dma[3]=1;
    if ((dma[4]&7U)!=6U || dma[5]!=0) fail(55);
    dma[3]=4;
}
static void selftest(void)
{
    uint32_t misa;
    __asm__ volatile ("csrr %0,misa" : "=r"(misa));
    if (misa!=0x40001100U) fail(60);
    ptrocos_uart_puts("PTROCOS DDR2 TEST\n");
    address_test();lane_test();access_fault_test();dma_test();
    while (timer_ticks<2) { }
    ptrocos_uart_puts("DDR2 DMA PASS\n");
    PTROCOS_MMIO32(0x4000000cU)=0x600d600dU;
}
static void full_sweep(void)
{
    volatile uint32_t *memory=(volatile uint32_t *)(uintptr_t)PTROCOS_DDR_BASE;
    const uint32_t count=PTROCOS_DDR_BYTES/4U;
    ptrocos_uart_puts("DDR2 FULL WRITE\n");
    for (uint32_t i=0;i<count;i++) memory[i]=pattern(i);
    ptrocos_uart_puts("DDR2 FULL READ\n");
    for (uint32_t i=0;i<count;i++) if (memory[i]!=pattern(i)) fail(70);
    ptrocos_uart_puts("DDR2 FULL PASS\n");
}
int main(void)
{
    ptrocos_timer_schedule(PTROCOS_CPU_HZ/1000U);
    __asm__ volatile ("csrw mie,%0" :: "r"(1U<<7));
    __asm__ volatile ("csrsi mstatus,8");
    selftest();
    ptrocos_uart_puts("r=selftest f=full-128MiB-sweep\n");
    for (;;) {
        int command=ptrocos_uart_getc();
        if (command=='r') selftest();
        else if (command=='f') full_sweep();
    }
}

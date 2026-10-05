#include "board.h"
void ptrocos_uart_putc(char value)
{
    while ((PTROCOS_MMIO32(0x40001004U) & 1U) == 0U) { }
    PTROCOS_MMIO32(0x40001000U) = (uint8_t)value;
}
void ptrocos_uart_puts(const char *text)
{
    while (*text) ptrocos_uart_putc(*text++);
}
int ptrocos_uart_getc(void)
{
    if ((PTROCOS_MMIO32(0x40001004U) & 2U) == 0U) return -1;
    return (int)(PTROCOS_MMIO32(0x40001008U) & 255U);
}
void ptrocos_uart_hex(uint32_t value)
{
    static const char digits[]="0123456789abcdef";
    for (int shift=28; shift>=0; shift-=4) ptrocos_uart_putc(digits[(value>>shift)&15U]);
}
uint64_t ptrocos_mtime(void)
{
    uint32_t high, low, check;
    do {
        high=PTROCOS_MMIO32(0x0200bffcU);
        low=PTROCOS_MMIO32(0x0200bff8U);
        check=PTROCOS_MMIO32(0x0200bffcU);
    } while (high!=check);
    return ((uint64_t)high<<32)|low;
}
void ptrocos_timer_schedule(uint32_t ticks)
{
    uint64_t next=ptrocos_mtime()+ticks;
    PTROCOS_MMIO32(0x02004004U)=0xffffffffU;
    PTROCOS_MMIO32(0x02004000U)=(uint32_t)next;
    PTROCOS_MMIO32(0x02004004U)=(uint32_t)(next>>32);
}
uint16_t ptrocos_crc16(uint16_t crc, const volatile void *data, size_t count)
{
    const volatile uint8_t *bytes=data;
    while (count--) {
        uint32_t result;
        uint32_t byte=*bytes++;
        __asm__ volatile (".insn r 0x0b,0,0,%0,%1,%2" : "=r"(result) : "r"((uint32_t)crc),"r"(byte));
        crc=(uint16_t)result;
    }
    return crc;
}

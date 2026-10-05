#ifndef PTROCOS_BOARD_H
#define PTROCOS_BOARD_H
#include <stdint.h>
#include <stddef.h>
#define PTROCOS_CPU_HZ 100000000U
#define PTROCOS_DDR_BASE 0x80000000U
#define PTROCOS_DDR_BYTES 0x08000000U
#define PTROCOS_DMA_BASE 0x4000a000U
#define PTROCOS_MMIO32(a) (*(volatile uint32_t *)(uintptr_t)(a))
void ptrocos_uart_putc(char value);
void ptrocos_uart_puts(const char *text);
int ptrocos_uart_getc(void);
void ptrocos_uart_hex(uint32_t value);
uint64_t ptrocos_mtime(void);
void ptrocos_timer_schedule(uint32_t ticks);
uint16_t ptrocos_crc16(uint16_t crc, const volatile void *data, size_t count);
#endif

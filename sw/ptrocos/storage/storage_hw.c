#include "storage_hw.h"
#include "board.h"
#include "FreeRTOS.h"
#include "task.h"
#define SD_BASE 0x4000d000U
#define SD_REG(n) PTROCOS_MMIO32(SD_BASE+(n))
static uint32_t control;
static volatile uint32_t *cancel_source;
void ptrocos_sd_cancel_source(volatile uint32_t *cancel) {cancel_source=cancel;}
uint32_t ptrocos_sd_status(void) {return SD_REG(4);}
uint32_t ptrocos_sd_exchanges(void) {return SD_REG(16);}
static int transfer(void *context,uint8_t value)
{
    (void)context;
    uint32_t status=SD_REG(4);
    if((status&25U)!=24U) return -1; // Present, powered, idle.
    SD_REG(8)=control|8U;
    SD_REG(0)=value;
    __asm__ volatile("fence iorw,iorw" ::: "memory");
    uint64_t begin=ptrocos_mtime();
    do {
        status=SD_REG(4);
        if((status&12U)!=8U) return -1; // Removal or engine fault.
        if(!(status&1U)) return (status&2U) ? (int)(SD_REG(0)&255U) : -1;
    } while(ptrocos_mtime()-begin<PTROCOS_CPU_HZ/1000U);
    SD_REG(8)=control|4U;
    return -1;
}
static void select_card(void *context,int selected)
{
    (void)context;control=(control&~2U)|(selected ? 2U : 0U);SD_REG(8)=control|8U;
}
static void power(void *context,int powered)
{
    (void)context;control=powered ? 1U : 0U;SD_REG(8)=control|8U;
}
static void speed(void *context,uint32_t hz)
{
    (void)context;
    uint32_t divider=hz ? (PTROCOS_CPU_HZ+2U*hz-1U)/(2U*hz) : 65535U;
    if(divider<4) divider=4;
    if(divider>65535) divider=65535;
    SD_REG(12)=divider;
}
static int present(void *context) {(void)context;return (SD_REG(4)&8U)!=0;}
static uint32_t milliseconds(void *context) {(void)context;return xTaskGetTickCount();}
static void pause_bus(void *context,uint32_t milliseconds)
{
    (void)context;
    if(milliseconds) vTaskDelay(pdMS_TO_TICKS(milliseconds));else taskYIELD();
}
static int cancelled(void *context) {(void)context;return cancel_source && *cancel_source;}
void ptrocos_sd_transport(struct sd_transport *bus)
{
    control=0;cancel_source=NULL;SD_REG(8)=8U;
    *bus=(struct sd_transport){transfer,select_card,power,speed,present,milliseconds,pause_bus,cancelled,NULL};
}

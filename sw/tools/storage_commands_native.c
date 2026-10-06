// Native transport/scheduler adapter. File commands, FatFs, diskio and SD are unchanged.
#include "storage_commands.h"
#include "storage_hw.h"
#include "storage_disk.h"
#include "board.h"
#include "semphr.h"
#include <pthread.h>
#include <sched.h>
#include <time.h>
static struct sd_transport original_bus;
static volatile uint32_t *cancel_source;
static pthread_mutex_t command_lock=PTHREAD_MUTEX_INITIALIZER;
static uint32_t yields;
SemaphoreHandle_t xSemaphoreCreateMutex(void) {return &command_lock;}
int xSemaphoreTake(SemaphoreHandle_t mutex,unsigned ticks)
{
    struct timespec deadline;
    if(!timespec_get(&deadline,TIME_UTC)) return 0;
    deadline.tv_nsec+=(long)ticks*1000000;
    if(deadline.tv_nsec>=1000000000) {deadline.tv_sec++;deadline.tv_nsec-=1000000000;}
    return pthread_mutex_timedlock(mutex,&deadline)==0;
}
int xSemaphoreGive(SemaphoreHandle_t mutex) {return pthread_mutex_unlock(mutex)==0;}
void storage_native_yield(void) {++yields;sched_yield();}
static int cancelled(void *context)
{
    return (cancel_source && *cancel_source) || original_bus.cancelled(context);
}
static int transfer(void *context,uint8_t value) {return original_bus.transfer(context,value);}
void ptrocos_sd_transport(struct sd_transport *bus) {*bus=original_bus;bus->cancelled=cancelled;bus->transfer=transfer;}
void storage_native_transfer(int (*callback)(void *,uint8_t)) {original_bus.transfer=callback;}
void ptrocos_sd_cancel_source(volatile uint32_t *cancel) {cancel_source=cancel;}
uint32_t ptrocos_sd_status(void) {return original_bus.present(original_bus.context) ? 24 : 0;}
uint32_t ptrocos_sd_exchanges(void) {return 0;}
uint16_t ptrocos_crc16(uint16_t crc,const volatile void *data,size_t count)
{
    const volatile uint8_t *bytes=data;
    while(count--) {
        crc^=*bytes++;
        for(unsigned i=0;i<8;i++) crc=(crc>>1)^((crc&1) ? 0xa001U : 0U);
    }
    return crc;
}
void storage_native_setup(const struct sd_transport *bus)
{
    original_bus=*bus;cancel_source=NULL;yields=0;ptrocos_storage_init();
}
uint32_t storage_native_yields(void) {return yields;}

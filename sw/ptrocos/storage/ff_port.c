#include "FreeRTOS.h"
#include "semphr.h"
#include "ff.h"
static SemaphoreHandle_t locks[FF_VOLUMES+1];
int ff_mutex_create(int volume)
{
    if(volume<0 || volume>FF_VOLUMES) return 0;
    if(!locks[volume]) locks[volume]=xSemaphoreCreateMutex();
    return locks[volume]!=NULL;
}
void ff_mutex_delete(int volume)
{
    if(volume>=0 && volume<=FF_VOLUMES && locks[volume]) {
        vSemaphoreDelete(locks[volume]);locks[volume]=NULL;
    }
}
int ff_mutex_take(int volume)
{
    return volume>=0 && volume<=FF_VOLUMES && locks[volume] &&
        xSemaphoreTake(locks[volume],pdMS_TO_TICKS(FF_FS_TIMEOUT))==pdTRUE;
}
void ff_mutex_give(int volume)
{
    configASSERT(volume>=0 && volume<=FF_VOLUMES && locks[volume]);
    configASSERT(xSemaphoreGive(locks[volume])==pdTRUE);
}

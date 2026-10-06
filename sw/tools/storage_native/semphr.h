#ifndef STORAGE_NATIVE_SEMPHR_H
#define STORAGE_NATIVE_SEMPHR_H
typedef void *SemaphoreHandle_t;
SemaphoreHandle_t xSemaphoreCreateMutex(void);
int xSemaphoreTake(SemaphoreHandle_t mutex,unsigned ticks);
int xSemaphoreGive(SemaphoreHandle_t mutex);
#endif

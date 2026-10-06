// Test-only scheduler surface; production commands retain their real FatFs/SD code.
#ifndef STORAGE_NATIVE_FREERTOS_H
#define STORAGE_NATIVE_FREERTOS_H
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
typedef uint32_t TickType_t;
#define pdTRUE 1
#define configASSERT(value) assert(value)
void storage_native_yield(void);
#define taskYIELD() storage_native_yield()
#endif

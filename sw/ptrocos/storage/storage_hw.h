#ifndef PTROCOS_STORAGE_HW_H
#define PTROCOS_STORAGE_HW_H
#include "sd_card.h"
void ptrocos_sd_transport(struct sd_transport *bus);
// Called only while the filesystem command owns its outer mutex.
void ptrocos_sd_cancel_source(volatile uint32_t *cancel);
uint32_t ptrocos_sd_status(void);
uint32_t ptrocos_sd_exchanges(void);
#endif

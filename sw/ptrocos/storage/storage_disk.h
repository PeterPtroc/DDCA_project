#ifndef PTROCOS_STORAGE_DISK_H
#define PTROCOS_STORAGE_DISK_H
#include "sd_card.h"
// Call once before any filesystem client starts. FatFs serializes each volume.
void ptrocos_storage_disk_setup(const struct sd_transport *bus);
struct sd_card *ptrocos_storage_disk_card(void);
#endif

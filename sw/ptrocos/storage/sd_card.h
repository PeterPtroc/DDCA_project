#ifndef PTROCOS_SD_CARD_H
#define PTROCOS_SD_CARD_H
#include <stdint.h>
#include <stddef.h>
enum sd_result {
    SD_OK,SD_NO_CARD,SD_TIMEOUT,SD_PROTOCOL,SD_CRC,SD_RANGE,
    SD_NOT_READY,SD_IO,SD_CANCELLED,SD_WRITE_REJECT
};
struct sd_transport {
    int (*transfer)(void *context,uint8_t outgoing); // Received byte, or -1.
    void (*select)(void *context,int selected);
    void (*power)(void *context,int powered);
    void (*speed)(void *context,uint32_t hz);
    int (*present)(void *context);
    uint32_t (*milliseconds)(void *context);
    void (*pause)(void *context,uint32_t milliseconds); // Zero yields fairly.
    int (*cancelled)(void *context); // Optional.
    void *context;
};
struct sd_card {
    struct sd_transport bus;
    uint32_t sectors,ocr,completed,reads,writes;
    uint8_t initialized,high_capacity,csd[16],cid[16];
    int last_error;
};
void sd_card_setup(struct sd_card *card,const struct sd_transport *bus);
int sd_card_initialize(struct sd_card *card);
int sd_card_ready(struct sd_card *card);
int sd_card_read(struct sd_card *card,uint32_t sector,void *buffer,uint32_t count);
int sd_card_write(struct sd_card *card,uint32_t sector,const void *buffer,uint32_t count);
int sd_card_sync(struct sd_card *card);
uint8_t sd_crc7(const uint8_t *data,size_t length);
uint16_t sd_crc16(const uint8_t *data,size_t length);
const char *sd_result_name(int result);
#endif

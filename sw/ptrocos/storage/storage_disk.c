#include "ff.h"
#include "diskio.h"
#include "storage_disk.h"
static struct sd_card card;
static unsigned configured;
void ptrocos_storage_disk_setup(const struct sd_transport *bus)
{
    sd_card_setup(&card,bus);configured=1;
}
struct sd_card *ptrocos_storage_disk_card(void) {return &card;}
static DRESULT result(int error)
{
    return error==SD_OK ? RES_OK : error==SD_RANGE ? RES_PARERR :
        error==SD_NO_CARD || error==SD_NOT_READY ? RES_NOTRDY : RES_ERROR;
}
DSTATUS disk_status(BYTE drive)
{
    if(drive || !configured) return STA_NOINIT;
    if(!card.bus.present(card.bus.context)) {card.initialized=0;return STA_NOINIT|STA_NODISK;}
    return sd_card_ready(&card) ? 0 : STA_NOINIT;
}
DSTATUS disk_initialize(BYTE drive)
{
    if(drive || !configured) return STA_NOINIT;
    return sd_card_initialize(&card)==SD_OK ? 0 : disk_status(drive);
}
DRESULT disk_read(BYTE drive,BYTE *buffer,LBA_t sector,UINT count)
{
    if(drive || !configured) return RES_PARERR;
    return result(sd_card_read(&card,sector,buffer,count));
}
DRESULT disk_write(BYTE drive,const BYTE *buffer,LBA_t sector,UINT count)
{
    if(drive || !configured) return RES_PARERR;
    return result(sd_card_write(&card,sector,buffer,count));
}
DRESULT disk_ioctl(BYTE drive,BYTE command,void *buffer)
{
    if(drive || !configured) return RES_PARERR;
    if(!sd_card_ready(&card)) return RES_NOTRDY;
    if(command==CTRL_SYNC) return result(sd_card_sync(&card));
    if(!buffer) return RES_PARERR;
    switch(command) {
      case GET_SECTOR_COUNT: *(LBA_t *)buffer=card.sectors;break;
      case GET_SECTOR_SIZE: *(WORD *)buffer=512;break;
      case GET_BLOCK_SIZE: *(DWORD *)buffer=1;break;
      default: return RES_PARERR;
    }
    return RES_OK;
}

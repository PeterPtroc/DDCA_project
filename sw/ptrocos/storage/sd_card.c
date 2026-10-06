#include "sd_card.h"

uint8_t sd_crc7(const uint8_t *data,size_t length)
{
    uint8_t crc=0;
    while(length--) {
        uint8_t byte=*data++;
        for(unsigned bit=0;bit<8;bit++) {
            crc=(uint8_t)(crc<<1);
            if((byte^crc)&0x80) crc^=9;
            byte=(uint8_t)(byte<<1);
        }
    }
    return crc&0x7f;
}
uint16_t sd_crc16(const uint8_t *data,size_t length)
{
    uint16_t crc=0;
    while(length--) {
        crc^=(uint16_t)*data++<<8;
        for(unsigned bit=0;bit<8;bit++) crc=(uint16_t)((crc<<1)^((crc&0x8000) ? 0x1021 : 0));
    }
    return crc;
}
const char *sd_result_name(int result)
{
    static const char *const names[]={"ok","no-card","timeout","protocol","crc","range",
        "not-ready","transport","cancelled","write-rejected"};
    return result>=0 && (unsigned)result<sizeof(names)/sizeof(names[0]) ? names[result] : "unknown";
}
void sd_card_setup(struct sd_card *c,const struct sd_transport *bus)
{
    *c=(struct sd_card){0};c->bus=*bus;
}
static int failed(struct sd_card *c,int error)
{
    c->last_error=error;
    if(error!=SD_RANGE && error!=SD_NOT_READY) c->initialized=0;
    return error;
}
static int transfer(struct sd_card *c,uint8_t value)
{
    if(!c->bus.present(c->bus.context)) {failed(c,SD_NO_CARD);return -1;}
    if(c->bus.cancelled && c->bus.cancelled(c->bus.context)) {failed(c,SD_CANCELLED);return -1;}
    int byte=c->bus.transfer(c->bus.context,value);
    if(byte<0 || byte>255) {
        int error=!c->bus.present(c->bus.context) ? SD_NO_CARD :
            c->bus.cancelled && c->bus.cancelled(c->bus.context) ? SD_CANCELLED : SD_IO;
        failed(c,error);return -1;
    }
    return byte;
}
static void release(struct sd_card *c)
{
    c->bus.select(c->bus.context,0);
    // Release the card's DO even after cancellation; do not depend on the
    // cancelled transfer wrapper to produce the required trailing clocks.
    if(c->bus.present(c->bus.context)) (void)c->bus.transfer(c->bus.context,255);
}
static int elapsed(struct sd_card *c,uint32_t begin,uint32_t milliseconds)
{
    return (uint32_t)(c->bus.milliseconds(c->bus.context)-begin)>=milliseconds;
}
static int ready_wait(struct sd_card *c,uint32_t timeout)
{
    uint32_t begin=c->bus.milliseconds(c->bus.context);
    for(unsigned tries=0;tries<65536;tries++) {
        int byte=transfer(c,255);
        if(byte<0) return c->last_error;
        if(byte==255) return SD_OK;
        if(elapsed(c,begin,timeout)) break;
        if((tries&63)==63) c->bus.pause(c->bus.context,1);
    }
    return failed(c,SD_TIMEOUT);
}
static int command(struct sd_card *c,uint8_t index,uint32_t argument)
{
    release(c);c->bus.select(c->bus.context,1);
    if(ready_wait(c,500)!=SD_OK) return -1;
    uint8_t frame[6]={(uint8_t)(0x40|index),(uint8_t)(argument>>24),
        (uint8_t)(argument>>16),(uint8_t)(argument>>8),(uint8_t)argument,0};
    frame[5]=(uint8_t)((sd_crc7(frame,5)<<1)|1);
    for(unsigned i=0;i<6;i++) if(transfer(c,frame[i])<0) return -1;
    for(unsigned tries=0;tries<10;tries++) {
        int response=transfer(c,255);
        if(response<0) return -1;
        if(!(response&0x80)) return response;
    }
    failed(c,SD_TIMEOUT);return -1;
}
static int response_ok(struct sd_card *c,int response)
{
    if(response<0) return c->last_error;
    if(response&8) return failed(c,SD_CRC);
    return response==0 ? SD_OK : failed(c,SD_PROTOCOL);
}
static int receive(struct sd_card *c,uint8_t *data,unsigned count)
{
    uint32_t begin=c->bus.milliseconds(c->bus.context);
    unsigned tries;
    for(tries=0;tries<65536;tries++) {
        int token=transfer(c,255);
        if(token<0) return c->last_error;
        if(token==0xfe) break;
        if(token!=255) return failed(c,SD_PROTOCOL);
        if(elapsed(c,begin,250)) return failed(c,SD_TIMEOUT);
        if((tries&63)==63) c->bus.pause(c->bus.context,1);
    }
    if(tries==65536) return failed(c,SD_TIMEOUT);
    for(unsigned i=0;i<count;i++) {
        int byte=transfer(c,255);if(byte<0) return c->last_error;data[i]=(uint8_t)byte;
    }
    int high=transfer(c,255);if(high<0) return c->last_error;
    int low=transfer(c,255);if(low<0) return c->last_error;
    if(sd_crc16(data,count)!=(uint16_t)((high<<8)|low)) return failed(c,SD_CRC);
    return SD_OK;
}
static int read_register(struct sd_card *c,uint8_t index,uint8_t data[16])
{
    int result=response_ok(c,command(c,index,0));
    if(result==SD_OK) result=receive(c,data,16);
    release(c);return result;
}
int sd_card_ready(struct sd_card *c)
{
    if(!c->bus.present(c->bus.context)) {failed(c,SD_NO_CARD);return 0;}
    return c->initialized;
}
int sd_card_initialize(struct sd_card *c)
{
    c->initialized=c->high_capacity=0;c->sectors=c->ocr=c->completed=0;c->last_error=SD_OK;
    if(!c->bus.present(c->bus.context)) return failed(c,SD_NO_CARD);
    c->bus.select(c->bus.context,0);c->bus.power(c->bus.context,0);
    c->bus.pause(c->bus.context,2);c->bus.speed(c->bus.context,400000);
    c->bus.power(c->bus.context,1);c->bus.pause(c->bus.context,10);
    for(unsigned i=0;i<10;i++) if(transfer(c,255)<0) goto error;
    if(command(c,0,0)!=1) {if(c->last_error==SD_OK) failed(c,SD_PROTOCOL);goto error;}
    int response=command(c,8,0x1aa);
    int version2=response==1;
    if(version2) {
        uint32_t echo=0;
        for(unsigned i=0;i<4;i++) {int byte=transfer(c,255);if(byte<0) goto error;echo=(echo<<8)|(unsigned)byte;}
        if(echo!=0x1aa) {failed(c,SD_PROTOCOL);goto error;}
    } else if(response!=5) {if(c->last_error==SD_OK) failed(c,SD_PROTOCOL);goto error;}
    uint32_t begin=c->bus.milliseconds(c->bus.context);
    unsigned tries;
    for(tries=0;tries<1000;tries++) {
        response=command(c,55,0);
        if(response<0) goto error;
        if(response!=0 && response!=1) {failed(c,SD_PROTOCOL);goto error;}
        response=command(c,41,version2 ? 0x40000000 : 0);
        if(response==0) break;
        if(response<0) goto error;
        if(response!=1) {failed(c,SD_PROTOCOL);goto error;}
        if(elapsed(c,begin,1000)) break;
        c->bus.pause(c->bus.context,1);
    }
    if(response!=0 || tries==1000) {failed(c,SD_TIMEOUT);goto error;}
    if(response_ok(c,command(c,58,0))!=SD_OK) goto error;
    for(unsigned i=0;i<4;i++) {int byte=transfer(c,255);if(byte<0) goto error;c->ocr=(c->ocr<<8)|(unsigned)byte;}
    if(!(c->ocr&0x80000000U) || !(c->ocr&0x00300000U)) {failed(c,SD_PROTOCOL);goto error;}
    c->high_capacity=(c->ocr>>30)&1U;
    if(c->high_capacity && !version2) {failed(c,SD_PROTOCOL);goto error;}
    // Enable CRC checking in the card as well as checking all received data.
    if(response_ok(c,command(c,59,1))!=SD_OK) goto error;
    if(!c->high_capacity && response_ok(c,command(c,16,512))!=SD_OK) goto error;
    if(read_register(c,9,c->csd)!=SD_OK || read_register(c,10,c->cid)!=SD_OK) goto error;
    uint64_t sectors;
    if((c->csd[0]>>6)==1 && c->high_capacity) {
        uint32_t size=((uint32_t)(c->csd[7]&63)<<16)|((uint32_t)c->csd[8]<<8)|c->csd[9];
        sectors=((uint64_t)size+1)*1024;
    } else if((c->csd[0]>>6)==0 && !c->high_capacity) {
        unsigned block_shift=c->csd[5]&15;
        unsigned multiplier=((c->csd[9]&3)<<1)|(c->csd[10]>>7);
        unsigned size=((c->csd[6]&3)<<10)|(c->csd[7]<<2)|(c->csd[8]>>6);
        if(block_shift<9 || block_shift>11) {failed(c,SD_PROTOCOL);goto error;}
        sectors=((uint64_t)size+1)<<(multiplier+2+block_shift-9);
    } else {failed(c,SD_PROTOCOL);goto error;}
    if(!sectors || sectors>UINT32_MAX) {failed(c,SD_RANGE);goto error;}
    c->sectors=(uint32_t)sectors;c->initialized=1;c->last_error=SD_OK;
    c->bus.speed(c->bus.context,12500000);
    release(c);return SD_OK;
error:
    release(c);return c->last_error;
}
static int bounds(struct sd_card *c,uint32_t sector,const void *buffer,uint32_t count)
{
    c->completed=0;c->last_error=SD_OK;
    if(!sd_card_ready(c)) return failed(c,c->last_error==SD_NO_CARD ? SD_NO_CARD : SD_NOT_READY);
    if(!buffer || !count || (uint64_t)sector+count>c->sectors ||
       (!c->high_capacity && (uint64_t)sector+count>(UINT32_MAX/512U)+1ULL)) return failed(c,SD_RANGE);
    return SD_OK;
}
int sd_card_read(struct sd_card *c,uint32_t sector,void *buffer,uint32_t count)
{
    int result=bounds(c,sector,buffer,count);if(result!=SD_OK) return result;
    uint8_t *data=buffer;
    for(unsigned i=0;i<count;i++) {
        uint32_t address=c->high_capacity ? sector+i : (sector+i)*512U;
        result=response_ok(c,command(c,17,address));
        if(result==SD_OK) result=receive(c,data,512);
        release(c);if(result!=SD_OK) return result;
        ++c->completed;++c->reads;data+=512;c->bus.pause(c->bus.context,0);
    }
    return SD_OK;
}
int sd_card_write(struct sd_card *c,uint32_t sector,const void *buffer,uint32_t count)
{
    int result=bounds(c,sector,buffer,count);if(result!=SD_OK) return result;
    const uint8_t *data=buffer;
    for(unsigned i=0;i<count;i++) {
        uint32_t address=c->high_capacity ? sector+i : (sector+i)*512U;
        result=response_ok(c,command(c,24,address));
        if(result!=SD_OK) {release(c);return result;}
        if(transfer(c,255)<0 || transfer(c,0xfe)<0) goto write_error;
        for(unsigned j=0;j<512;j++) if(transfer(c,data[j])<0) goto write_error;
        uint16_t crc=sd_crc16(data,512);
        if(transfer(c,(uint8_t)(crc>>8))<0 || transfer(c,(uint8_t)crc)<0) goto write_error;
        int token=-1;
        for(unsigned tries=0;tries<10;tries++) {token=transfer(c,255);if(token<0) goto write_error;if(token!=255) break;}
        if((token&31)!=5) {failed(c,(token&31)==11 ? SD_CRC : token==255 ? SD_TIMEOUT : SD_WRITE_REJECT);goto write_error;}
        if(ready_wait(c,500)!=SD_OK) goto write_error;
        release(c);++c->completed;++c->writes;data+=512;c->bus.pause(c->bus.context,0);
        continue;
write_error:
        release(c);return c->last_error;
    }
    return SD_OK;
}
int sd_card_sync(struct sd_card *c)
{
    c->last_error=SD_OK;
    if(!sd_card_ready(c)) return failed(c,c->last_error==SD_NO_CARD ? SD_NO_CARD : SD_NOT_READY);
    c->bus.select(c->bus.context,1);int result=ready_wait(c,500);release(c);return result;
}

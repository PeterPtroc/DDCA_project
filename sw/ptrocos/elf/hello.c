#include "app_api.h"
static volatile uint32_t initialized=0x13579bdfU;
static volatile uint32_t zeroed[64];
int app_main(const struct ptrocos_app_api *api,int argc,const char *const *argv)
{
    if(api->version!=1 || initialized!=0x13579bdfU || argc<1 || !argv[0]) return 90;
    for(unsigned i=0;i<64;i++) if(zeroed[i]) return 91;
    if(api->write("ELF HELLO BSS PASS\r\n",20)!=20) return 92;
    for(int i=1;i<argc;i++) {
        unsigned n=0;while(argv[i][n] && n<128) ++n;
        if(api->write(argv[i],n)!=(int)n || api->write("\r\n",2)!=2) return 93;
    }
    for(unsigned i=0;i<64;i++) zeroed[i]=0xa55a0000U+i;
    initialized=0;
    api->yield();
    return 37;
}

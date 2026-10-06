#include "app_api.h"
int app_main(const struct ptrocos_app_api *api,int argc,const char *const *argv)
{
    (void)api;(void)argc;(void)argv;
    __asm__ volatile(".word 0xffffffff");
    return 99;
}

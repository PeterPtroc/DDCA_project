#include "app_api.h"
int app_main(const struct ptrocos_app_api *api,int argc,const char *const *argv)
{
    (void)api;(void)argc;(void)argv;
    for(;;) __asm__ volatile("nop");
}

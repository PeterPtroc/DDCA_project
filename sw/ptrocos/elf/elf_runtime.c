#include "elf_runtime.h"
#include "app_api.h"
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "storage/storage_commands.h"
#include "apps.h"
#include <string.h>
static SemaphoreHandle_t lock;
static TaskHandle_t owner;
static volatile uint32_t active,reason,fault_pc,fault_cause;
static TickType_t deadline;
static volatile uint32_t *cancel;
static void (*writer)(void *,const char *);
static void *output_context;
uint32_t ptrocos_app_saved_sp;
extern void *volatile pxCurrentTCB;
extern int ptrocos_app_call(uint32_t,const struct ptrocos_app_api *,int,const char *const *);
extern void ptrocos_app_abort(void);
static void number(const char *name,uint32_t value)
{
    char text[11];unsigned p=10;text[10]=0;
    do {text[--p]=(char)('0'+value%10);value/=10;} while(value);
    writer(output_context,name);writer(output_context,&text[p]);
}
int ptrocos_elf_memory_write(void *context,uint32_t address,const void *data,unsigned count)
{
    (void)context;
    // Decoder validated the whole image. This check also protects diagnostic callers.
    uint64_t end=(uint64_t)address+count;
    if(!((address>=PTROCOS_APP_CODE_BASE && end<=PTROCOS_APP_CODE_END) ||
         (address>=PTROCOS_APP_DATA_BASE && end<=PTROCOS_APP_DATA_END))) return ELF_OUTPUT;
    volatile uint8_t *to=(volatile uint8_t *)(uintptr_t)address;const uint8_t *from=data;
    while(count--) *to++=*from++;
    return ELF_OK;
}
void ptrocos_elf_progress(void *context) {(void)context;taskYIELD();}
static int api_cancelled(void) {return (cancel && *cancel) || (int32_t)(xTaskGetTickCount()-deadline)>=0;}
static void api_yield(void) {vTaskDelay(1);}
static int api_write(const char *text,unsigned count)
{
    uint32_t address=(uint32_t)(uintptr_t)text;uint64_t end=(uint64_t)address+count;
    if(count>512 || !((address>=PTROCOS_APP_CODE_BASE && end<=PTROCOS_APP_CODE_END) ||
       (address>=PTROCOS_APP_DATA_BASE && end<=PTROCOS_APP_STACK_END) ||
       (address>=0x10000000U && end<=0x10010000U))) return -1;
    unsigned done=0;
    while(done<count && !api_cancelled()) {
        char byte[2]={text[done],0};writer(output_context,byte);++done;
    }
    return (int)done;
}
static const struct ptrocos_app_api api={1,api_write,api_yield,api_cancelled};
static uint32_t *saved_context(void)
{
    if(!active || pxCurrentTCB!=owner) return NULL;
    uint32_t *frame=*(uint32_t **)pxCurrentTCB;
    uint32_t address=(uint32_t)(uintptr_t)frame;
    // Frozen RV32 port: 31 words, resume PC at 0, critical nesting at 30.
    return address>=PTROCOS_APP_DATA_END+64 && address<=PTROCOS_APP_STACK_END-124 ? frame : NULL;
}
static void abort_frame(uint32_t *frame,uint32_t why)
{
    reason=why;frame[0]=(uint32_t)(uintptr_t)ptrocos_app_abort;
    frame[30]=0;
}
void vApplicationTickHook(void)
{
    uint32_t *frame=saved_context();
    // Never force an exit inside a ROM API operation or an RTOS critical section.
    if(frame && frame[0]>=PTROCOS_APP_CODE_BASE && frame[0]<PTROCOS_APP_CODE_END && !frame[30]) {
        if(cancel && *cancel) abort_frame(frame,1);
        else if((int32_t)(xTaskGetTickCountFromISR()-deadline)>=0) abort_frame(frame,2);
    }
}
int ptrocos_elf_exception(uint32_t cause,uint32_t resume_pc)
{
    uint32_t *frame=saved_context();uint32_t pc=resume_pc-4;
    if(!frame || pc<PTROCOS_APP_CODE_BASE || frame[30]) return 0;
    fault_pc=pc;fault_cause=cause;abort_frame(frame,3);return 1;
}
void ptrocos_elf_init(void) {lock=xSemaphoreCreateMutex();configASSERT(lock!=NULL);}
static int execute(const struct elf_image *image,int argc,const char *const *argv,unsigned timeout)
{
    if(!image->loaded) return -1;
    volatile uint32_t *stack=(volatile uint32_t *)(uintptr_t)PTROCOS_APP_DATA_END;
    for(unsigned i=0;i<1024;i++) stack[i]=0xa5a5a5a5U;
    reason=0;fault_pc=0;fault_cause=0;owner=xTaskGetCurrentTaskHandle();
    deadline=xTaskGetTickCount()+timeout;active=1;
    __asm__ volatile("fence iorw,iorw" ::: "memory");
    int result=ptrocos_app_call(image->entry,&api,argc,argv);
    active=0;owner=NULL;
    unsigned guard=1;for(unsigned i=0;i<16;i++) if(stack[i]!=0xa5a5a5a5U) guard=0;
    if(!guard) reason=4;
    if(reason==1) writer(output_context,"ELF cancelled\r\n");
    else if(reason==2) writer(output_context,"ELF timeout\r\n");
    else if(reason==3) {number("ELF fault cause=",fault_cause);number(" pc=",fault_pc);writer(output_context,"\r\n");}
    else if(reason==4) writer(output_context,"ELF stack guard damaged\r\n");
    else {number("ELF returned code=",(uint32_t)result);writer(output_context,"\r\n");}
    return reason ? -(int)reason : result;
}
struct embedded {const unsigned char *data;volatile uint32_t *cancel;};
static int embedded_read(void *context,uint32_t offset,void *data,unsigned count)
{struct embedded *s=context;memcpy(data,s->data+offset,count);return ELF_OK;}
static int embedded_cancel(void *context) {struct embedded *s=context;return *s->cancel!=0;}
static int diagnostic(const unsigned char *data,unsigned bytes,unsigned timeout)
{
    struct embedded stream={data,cancel};struct elf_source source={bytes,embedded_read,embedded_cancel,&stream};
    struct elf_sink sink={ptrocos_elf_memory_write,ptrocos_elf_progress,NULL};struct elf_image image;
    int loaded=ptrocos_elf_load(&source,&sink,&image);if(loaded) return -10-loaded;
    const char *argv[]={"diagnostic"};return execute(&image,1,argv,timeout);
}
int ptrocos_elf_command(unsigned argc,char **argv,void (*write)(void *,const char *),void *context,volatile uint32_t *stop)
{
    if(!argc || (strcmp(argv[0],"run") && strcmp(argv[0],"elf"))) return 0;
    int run=!strcmp(argv[0],"run");
    if((run && argc<2) || (!run && (argc!=2 || (strcmp(argv[1],"info") && strcmp(argv[1],"test"))))) {
        write(context,"usage: run <path> [args] | elf info | elf test\r\n");return 1;
    }
    while(xSemaphoreTake(lock,1)!=pdTRUE) if(*stop) return 1;
    if(*stop) {(void)xSemaphoreGive(lock);return 1;}
    writer=write;output_context=context;cancel=stop;
    if(run) {
        struct elf_image image;
        if(ptrocos_storage_elf(argv[1],&image,write,context,stop)==ELF_OK)
            (void)execute(&image,(int)argc-1,(const char *const *)(argv+1),5000);
    } else if(!strcmp(argv[1],"info")) {
        write(context,"ELF32 RV32IM ILP32 ABI=1 code=0x00010000+16KiB data=0x80800000+1020KiB stack=4KiB timeout=5000ms trusted M-mode\r\n");
    } else {
        int a=diagnostic(app_hello,sizeof(app_hello),1000);
        int b=diagnostic(app_hello,sizeof(app_hello),1000);
        int c=diagnostic(app_fault,sizeof(app_fault),1000);
        int d=diagnostic(app_loop,sizeof(app_loop),40);
        if(!*stop) write(context,a==37 && b==37 && c==-3 && d==-2 ?
            "ELF TEST PASS hello reload-BSS fault timeout shell-return\r\n" : "ELF TEST FAILED\r\n");
    }
    cancel=NULL;writer=NULL;output_context=NULL;
    configASSERT(xSemaphoreGive(lock)==pdTRUE);return 1;
}

#include "shell.h"
#include <stddef.h>
const char *const shell_commands[]={"help","echo","clear","uname","uptime","mem","video","kbd","tasks","sleep","ddrtest"
#ifdef PTROCOS_STORAGE
    ,"mount","umount","sdinfo","fscheck","ls","cat","hexdump"
#endif
#ifdef PTROCOS_GRAPHICS
    ,"gfx"
#ifdef PTROCOS_MEDIA
    ,"bmp","wav","audio"
#ifdef PTROCOS_VIDEO
    ,"play"
#endif
#endif
#endif
};
const unsigned shell_command_count=sizeof(shell_commands)/sizeof(shell_commands[0]);
int shell_parse(char *line,char **argv,unsigned *argc)
{
    char *read=line,*write=line;
    *argc=0;
    while(*read) {
        while(*read==' ' || *read=='\t') ++read;
        if(!*read) break;
        if(*argc==SHELL_ARGS) return SHELL_TOO_MANY_ARGS;
        argv[(*argc)++]=write;
        char quote=0;
        while(*read) {
            char ch=*read++;
            if(ch=='\\' && quote!='\'') {
                if(!*read) return SHELL_ESCAPE_ERROR;
                *write++=*read++;
            } else if(quote) {
                if(ch==quote) quote=0;
                else *write++=ch;
            } else if(ch=='\'' || ch=='"') quote=ch;
            else if(ch==' ' || ch=='\t') break;
            else *write++=ch;
        }
        if(quote) return SHELL_QUOTE_ERROR;
        *write++=0;
    }
    return SHELL_OK;
}
int shell_u32(const char *text,uint32_t *value)
{
    if(!*text) return 0;
    uint32_t result=0;
    while(*text) {
        unsigned digit=(unsigned char)*text++-'0';
        if(digit>9 || result>(UINT32_MAX-digit)/10U) return 0;
        result=result*10U+digit;
    }
    *value=result;return 1;
}
const char *shell_complete(const char *prefix)
{
    const char *match=NULL;
    for(unsigned i=0;i<shell_command_count;i++) {
        const char *a=prefix,*b=shell_commands[i];
        while(*a && *a==*b) {++a;++b;}
        if(!*a) {if(match) return NULL;match=shell_commands[i];}
    }
    return match;
}

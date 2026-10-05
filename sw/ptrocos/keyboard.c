#include "keyboard.h"
// PS/2 scan code set 2, US layout. No heap or locale dependencies.
static const uint8_t plain[128]={
    [0x0d]='\t',[0x0e]='`',[0x15]='q',[0x16]='1',[0x1a]='z',[0x1b]='s',
    [0x1c]='a',[0x1d]='w',[0x1e]='2',[0x21]='c',[0x22]='x',[0x23]='d',
    [0x24]='e',[0x25]='4',[0x26]='3',[0x29]=' ',[0x2a]='v',[0x2b]='f',
    [0x2c]='t',[0x2d]='r',[0x2e]='5',[0x31]='n',[0x32]='b',[0x33]='h',
    [0x34]='g',[0x35]='y',[0x36]='6',[0x3a]='m',[0x3b]='j',[0x3c]='u',
    [0x3d]='7',[0x3e]='8',[0x41]=',',[0x42]='k',[0x43]='i',[0x44]='o',
    [0x45]='0',[0x46]='9',[0x49]='.',[0x4a]='/',[0x4b]='l',[0x4c]=';',
    [0x4d]='p',[0x4e]='-',[0x52]='\'',[0x54]='[',[0x55]='=',[0x5a]='\n',
    [0x5b]=']',[0x5d]='\\',[0x66]='\b',[0x76]=27
};
static const uint8_t shifted[128]={
    [0x0e]='~',[0x16]='!',[0x1e]='@',[0x25]='$',[0x26]='#',[0x2e]='%',
    [0x36]='^',[0x3d]='&',[0x3e]='*',[0x41]='<',[0x45]=')',[0x46]='(',
    [0x49]='>',[0x4a]='?',[0x4c]=':',[0x4e]='_',[0x52]='"',[0x54]='{',
    [0x55]='+',[0x5b]='}',[0x5d]='|'
};
void ptrocos_keyboard_reset(struct ptrocos_keyboard *state)
{
    *state=(struct ptrocos_keyboard){0};
}
int ptrocos_keyboard_decode(struct ptrocos_keyboard *state,uint8_t scan)
{
    if(state->pause_bytes) {--state->pause_bytes;return -1;}
    if(scan==0xe1) {state->pause_bytes=7;state->extended=state->release=0;return -1;}
    if(scan==0xe0) {state->extended=1;return -1;}
    if(scan==0xf0) {state->release=1;return -1;}
    uint8_t extended=state->extended,up=state->release;
    state->extended=state->release=0;
    // BAT/ACK and transport error bytes must not turn into characters.
    if(scan>=128 || scan==0) return -1;
    if(!extended && (scan==0x12 || scan==0x59)) {
        if(scan==0x12) state->left_shift=!up;
        else state->right_shift=!up;
        return -1;
    }
    if(scan==0x14) {
        if(extended) state->right_ctrl=!up;
        else state->left_ctrl=!up;
        return -1;
    }
    if(!extended && scan==0x58) {
        if(!up && !state->caps_down) state->caps^=1;
        state->caps_down=!up;return -1;
    }
    if(up) return -1;
    if(extended) {
        switch(scan) {
        case 0x75:return KEY_UP;case 0x72:return KEY_DOWN;
        case 0x6b:return KEY_LEFT;case 0x74:return KEY_RIGHT;
        case 0x6c:return KEY_HOME;case 0x69:return KEY_END;
        case 0x71:return KEY_DELETE;case 0x70:return KEY_INSERT;
        case 0x7d:return KEY_PAGE_UP;case 0x7a:return KEY_PAGE_DOWN;
        case 0x5a:return '\n';case 0x4a:return '/';default:return -1;
        }
    }
    int ch=plain[scan];
    if(!ch) return -1;
    uint8_t shift=state->left_shift || state->right_shift;
    if(ch>='a' && ch<='z') {
        if(state->left_ctrl || state->right_ctrl) return ch-'a'+1;
        if(shift^state->caps) ch-=32;
    } else if(shift && shifted[scan]) ch=shifted[scan];
    return ch;
}

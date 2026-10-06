#include "tty.h"
#include "keyboard.h"
#include "shell.h"
static void copy(char *to,const char *from)
{
    while((*to++=*from++)!=0) { }
}
static void text(struct tty *t,const char *s) {t->callbacks.text(t->callbacks.context,s);}
static void redraw(struct tty *t) {t->callbacks.redraw(t->callbacks.context,t->line,t->length,t->cursor);}
static void reset_line(struct tty *t)
{
    t->line[0]=0;t->length=t->cursor=t->browse=t->overflow=t->escape=t->escape_number=0;
}
void tty_init(struct tty *t,const struct tty_callbacks *callbacks)
{
    *t=(struct tty){0};t->callbacks=*callbacks;redraw(t);
}
static void erase(struct tty *t,unsigned start,unsigned count)
{
    for(unsigned i=start;i+count<=t->length;i++) t->line[i]=t->line[i+count];
    t->length-=count;t->cursor=start;
}
static void history(struct tty *t,int older)
{
    if(older) {
        if(t->browse==t->history_count) {text(t,"\a");return;}
        if(!t->browse) copy(t->draft,t->line);
        ++t->browse;
    } else {
        if(!t->browse) return;
        --t->browse;
    }
    copy(t->line,t->browse ? t->history[(t->history_next+TTY_HISTORY-t->browse)%TTY_HISTORY] : t->draft);
    t->length=0;while(t->line[t->length]) ++t->length;
    t->cursor=t->length;t->overflow=0;
}
void tty_key(struct tty *t,int key)
{
    if(key==TTY_INPUT_LOST) {
        text(t,"\r\ninput lost; line discarded\r\n");reset_line(t);redraw(t);return;
    }
    if(key=='\r' || key=='\n') {
        text(t,"\r\n");
        if(t->overflow) text(t,"line too long; discarded\r\n");
        else if(t->length) {
            copy(t->history[t->history_next],t->line);
            t->history_next=(t->history_next+1)%TTY_HISTORY;
            if(t->history_count<TTY_HISTORY) ++t->history_count;
            t->callbacks.command(t->callbacks.context,t->line);
        }
        reset_line(t);redraw(t);return;
    }
    if(key==3 || key==27) {text(t,"^C\r\n");reset_line(t);redraw(t);return;}
    if(key==12) {t->callbacks.clear(t->callbacks.context);redraw(t);return;}
    if(key==KEY_UP) history(t,1);
    else if(key==KEY_DOWN) history(t,0);
    else if(key==KEY_LEFT || key==2) {if(t->cursor) --t->cursor;}
    else if(key==KEY_RIGHT || key==6) {if(t->cursor<t->length) ++t->cursor;}
    else if(key==KEY_HOME || key==1) t->cursor=0;
    else if(key==KEY_END || key==5) t->cursor=t->length;
    else if(key=='\b' || key==127) {if(t->cursor) erase(t,t->cursor-1,1);}
    else if(key==KEY_DELETE) {if(t->cursor<t->length) erase(t,t->cursor,1);}
    else if(key==21) reset_line(t);
    else if(key==11) erase(t,t->cursor,t->length-t->cursor);
    else if(key==23) {
        unsigned start=t->cursor;
        while(start && t->line[start-1]==' ') --start;
        while(start && t->line[start-1]!=' ') --start;
        erase(t,start,t->cursor-start);
    } else if(key=='\t') {
        if(t->cursor!=t->length) return;
        const char *match=shell_complete(t->line);
        if(!match) {text(t,"\a");return;}
        unsigned length=0;while(match[length]) ++length;
        if(length+1>=TTY_LINE_CAP) return;
        copy(t->line,match);t->line[length++]=' ';t->line[length]=0;
        t->length=t->cursor=length;
    } else if(key>=32 && key<127) {
        if(t->length==TTY_LINE_CAP-1) {t->overflow=1;text(t,"\a");return;}
        for(unsigned i=t->length+1;i>t->cursor;i--) t->line[i]=t->line[i-1];
        t->line[t->cursor++]=(char)key;++t->length;
    } else return;
    redraw(t);
}
void tty_uart_byte(struct tty *t,uint8_t byte)
{
    if(byte=='\n' && t->last_cr) {t->last_cr=0;return;}
    t->last_cr=byte=='\r';
    if(byte==3 || byte==21) {t->escape=0;tty_key(t,byte);return;}
    if(!t->escape) {if(byte==27) {t->escape=1;return;}tty_key(t,byte);return;}
    if(t->escape==1) {
        if(byte=='[' || byte=='O') {t->escape=2;t->escape_number=0;}
        else t->escape=0;
        return;
    }
    if(byte>='0' && byte<='9') {
        if(t->escape_number<1000) t->escape_number=t->escape_number*10+byte-'0';
        else t->escape=0;
        return;
    }
    unsigned number=t->escape_number;t->escape=0;
    int key=-1;
    if(byte=='A') key=KEY_UP;else if(byte=='B') key=KEY_DOWN;
    else if(byte=='C') key=KEY_RIGHT;else if(byte=='D') key=KEY_LEFT;
    else if(byte=='H') key=KEY_HOME;else if(byte=='F') key=KEY_END;
    else if(byte=='~') {
        if(number==1 || number==7) key=KEY_HOME;
        else if(number==4 || number==8) key=KEY_END;
        else if(number==3) key=KEY_DELETE;
    }
    if(key>=0) tty_key(t,key);
}
void tty_uart_timeout(struct tty *t) {t->escape=t->escape_number=0;}

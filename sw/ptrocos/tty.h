#ifndef PTROCOS_TTY_H
#define PTROCOS_TTY_H
#include <stdint.h>
#define TTY_LINE_CAP 64
#define TTY_HISTORY 4
#define TTY_PROMPT "ptroc> "
#define TTY_INPUT_LOST 0x1ff
struct tty_callbacks {
    void (*text)(void *,const char *);
    void (*redraw)(void *,const char *,unsigned,unsigned);
    void (*clear)(void *);
    void (*command)(void *,const char *);
    void *context;
};
struct tty {
    struct tty_callbacks callbacks;
    char line[TTY_LINE_CAP],draft[TTY_LINE_CAP],history[TTY_HISTORY][TTY_LINE_CAP];
    unsigned length,cursor,history_count,history_next,browse;
    unsigned escape,escape_number,overflow,last_cr;
};
void tty_init(struct tty *tty,const struct tty_callbacks *callbacks);
void tty_key(struct tty *tty,int key);
void tty_uart_byte(struct tty *tty,uint8_t byte);
void tty_uart_timeout(struct tty *tty);
#endif

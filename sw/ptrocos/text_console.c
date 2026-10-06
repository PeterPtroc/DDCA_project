#include "board.h"
#include "text_console.h"
static unsigned column,row;
static volatile uint32_t *const cells=(volatile uint32_t *)(uintptr_t)0x40010000U;
static void cursor(void) {PTROCOS_MMIO32(0x4000b004U)=row*80U+column;}
void ptrocos_text_clear(void)
{
    for(unsigned i=0;i<2400;i++) cells[i]=0x0720;
    column=row=0;cursor();PTROCOS_MMIO32(0x4000b000U)=7;
}
void ptrocos_text_putc(char value)
{
    unsigned ch=(unsigned char)value;
    if(ch=='\r') column=0;
    else if(ch=='\n') {column=0;++row;}
    else if(ch=='\b') {
        if(column) --column;
        else if(row) {--row;column=79;}
        cells[row*80U+column]=0x0720;
    } else if(ch=='\t') {
        unsigned spaces=8U-(column&7U);
        while(spaces--) ptrocos_text_putc(' ');
        return;
    } else if(ch>=32 && ch<127) {
        cells[row*80U+column]=0x0700U|ch;
        if(++column==80) {column=0;++row;}
    }
    if(row==30) {
        for(unsigned i=0;i<2320;i++) cells[i]=cells[i+80];
        for(unsigned i=2320;i<2400;i++) cells[i]=0x0720;
        row=29;
    }
    cursor();
}
void ptrocos_text_puts(const char *text)
{
    while(*text) ptrocos_text_putc(*text++);
}
void ptrocos_text_redraw(const char *prompt,const char *line,unsigned length,unsigned caret)
{
    unsigned prefix=0;while(prompt[prefix] && prefix<80) ++prefix;
    // TTY's 63-byte input plus its seven-byte prompt fits on one 80-cell row.
    for(unsigned i=0;i<80;i++) {
        unsigned ch=i<prefix ? (unsigned char)prompt[i] :
                    i-prefix<length ? (unsigned char)line[i-prefix] : ' ';
        cells[row*80U+i]=0x0700U|ch;
    }
    column=prefix+caret;if(column>=80) column=79;
    cursor();
}

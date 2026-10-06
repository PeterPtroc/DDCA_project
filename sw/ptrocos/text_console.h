#ifndef PTROCOS_TEXT_CONSOLE_H
#define PTROCOS_TEXT_CONSOLE_H
void ptrocos_text_clear(void);
void ptrocos_text_putc(char value);
void ptrocos_text_puts(const char *text);
void ptrocos_text_redraw(const char *prompt,const char *line,unsigned length,unsigned caret);
#endif

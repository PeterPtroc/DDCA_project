#include <stddef.h>
size_t strlen(const char *text)
{
    size_t length=0;
    while(text[length]) ++length;
    return length;
}
char *strchr(const char *text,int value)
{
    unsigned char ch=(unsigned char)value;
    do {if((unsigned char)*text==ch) return (char *)text;} while(*text++);
    return NULL;
}

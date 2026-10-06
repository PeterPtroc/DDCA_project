#include <stddef.h>
size_t strlen(const char *text)
{
    size_t length=0;
    while(text[length]) ++length;
    return length;
}

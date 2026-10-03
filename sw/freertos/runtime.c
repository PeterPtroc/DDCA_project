#include <stddef.h>
#include <stdint.h>

void * memcpy( void * destination, const void * source, size_t count )
{
    uint8_t * out = ( uint8_t * ) destination;
    const uint8_t * in = ( const uint8_t * ) source;
    while( count-- != 0U )
    {
        *out++ = *in++;
    }
    return destination;
}

void * memset( void * destination, int value, size_t count )
{
    uint8_t * out = ( uint8_t * ) destination;
    while( count-- != 0U )
    {
        *out++ = ( uint8_t ) value;
    }
    return destination;
}

int memcmp( const void * left, const void * right, size_t count )
{
    const uint8_t * a = ( const uint8_t * ) left;
    const uint8_t * b = ( const uint8_t * ) right;
    while( count-- != 0U )
    {
        if( *a != *b )
        {
            return ( int ) *a - ( int ) *b;
        }
        a++;
        b++;
    }
    return 0;
}


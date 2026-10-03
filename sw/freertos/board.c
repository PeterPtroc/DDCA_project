#include "board.h"

#define MMIO32( address ) ( *( volatile uint32_t * ) ( uintptr_t ) ( address ) )

#define GPIO_BASE       0x40000000UL
#define UART_BASE       0x40001000UL
#define CAPTURE_BASE    0x40004000UL
#define LIVE_BASE       0x40005000UL
#define PERF_BASE       0x40006000UL
#define BUTTON_BASE     0x40007000UL
#define DISPLAY_BASE    0x40008000UL
#define MEASURE_BASE    0x40009000UL
#define CAPTURE_WINDOW  0x40010000UL

void board_uart_putc( char value )
{
    while( ( MMIO32( UART_BASE + 4 ) & 1U ) == 0U )
    {
    }
    MMIO32( UART_BASE ) = ( uint32_t ) ( uint8_t ) value;
}

void board_uart_puts( const char * text )
{
    while( *text != '\0' )
    {
        board_uart_putc( *text++ );
    }
}

void board_uart_put_hex32( uint32_t value )
{
    static const char digits[] = "0123456789abcdef";
    int shift;
    for( shift = 28; shift >= 0; shift -= 4 )
    {
        board_uart_putc( digits[ ( value >> ( uint32_t ) shift ) & 0xfU ] );
    }
}

int board_uart_try_getc( char * value )
{
    if( ( MMIO32( UART_BASE + 4 ) & 2U ) == 0U )
    {
        return 0;
    }
    *value = ( char ) ( MMIO32( UART_BASE + 8 ) & 0xffU );
    return 1;
}

void board_set_leds( uint16_t value )
{
    MMIO32( GPIO_BASE ) = value;
}

void board_set_test_result( uint32_t value )
{
    MMIO32( GPIO_BASE + 12 ) = value;
}

void board_display_hex32( uint32_t value )
{
    uint32_t low = 0U;
    uint32_t high = 0U;
    uint32_t index;
    for( index = 0; index < 4U; index++ )
    {
        low |= ( ( value >> ( index * 4U ) ) & 0xfU ) << ( index * 8U );
        high |= ( ( value >> ( ( index + 4U ) * 4U ) ) & 0xfU ) << ( index * 8U );
    }
    MMIO32( DISPLAY_BASE ) = low;
    MMIO32( DISPLAY_BASE + 4 ) = high;
    MMIO32( DISPLAY_BASE + 12 ) = 1U;
}

void board_scope_measure( ScopeMeasurement * measurement )
{
    uint32_t first;
    uint32_t second;
    do
    {
        first = MMIO32( MEASURE_BASE + 4 );
        measurement->high = MMIO32( MEASURE_BASE + 8 );
        second = MMIO32( MEASURE_BASE + 4 );
    } while( first != second );

    measurement->period = second;
    measurement->valid = MMIO32( MEASURE_BASE ) & 1U;
    measurement->low = ( second >= measurement->high ) ?
                       second - measurement->high : 0U;
    measurement->frequency = ( second != 0U ) ? 100000000UL / second : 0U;
}

uint32_t board_scope_measure_status( void )
{
    return MMIO32( MEASURE_BASE );
}

void board_scope_set_average( uint32_t enabled )
{
    MMIO32( MEASURE_BASE ) = 1U | ( ( enabled & 1U ) << 2 );
}

void board_scope_set_live( uint32_t enabled, uint32_t hold )
{
    MMIO32( LIVE_BASE ) = ( enabled & 1U ) | ( ( hold & 1U ) << 1 );
}

void board_scope_set_mode( uint32_t mode )
{
    MMIO32( LIVE_BASE + 8 ) = mode & 3U;
}

void board_scope_set_edge( uint32_t falling )
{
    MMIO32( LIVE_BASE + 12 ) = falling & 1U;
    MMIO32( CAPTURE_BASE + 8 ) = falling & 1U;
}

void board_scope_set_timebase( uint32_t divider )
{
    uint32_t safe_divider = ( divider == 0U ) ? 1U : divider;
    MMIO32( LIVE_BASE + 16 ) = safe_divider;
    MMIO32( CAPTURE_BASE + 12 ) = safe_divider;
}

void board_scope_start_single( void )
{
    board_scope_set_live( 0U, 0U );
    board_scope_set_mode( BOARD_SCOPE_SINGLE );
    board_capture_start();
    board_scope_set_live( 1U, 0U );
}

void board_capture_start( void )
{
    MMIO32( CAPTURE_BASE ) = 2U;
    MMIO32( CAPTURE_BASE ) = 1U;
}

uint32_t board_switches( void )
{
    return MMIO32( BUTTON_BASE + 8 );
}

uint32_t board_button_events( void )
{
    return MMIO32( BUTTON_BASE + 4 );
}

uint32_t board_capture_status( void )
{
    return MMIO32( CAPTURE_BASE + 4 );
}

uint32_t board_capture_sample_div( void )
{
    return MMIO32( CAPTURE_BASE + 12 );
}

uint32_t board_capture_trigger_index( void )
{
    return MMIO32( CAPTURE_BASE + 24 ) & 0xfffU;
}

uint32_t board_capture_sample( uint32_t index )
{
    return MMIO32( CAPTURE_WINDOW + ( ( index & 0xfffU ) << 2 ) ) & 1U;
}

uint32_t board_perf_counter( uint32_t index )
{
    return ( index < 9U ) ? MMIO32( PERF_BASE + ( index << 2 ) ) : 0U;
}

#ifndef DDCA_BOARD_H
#define DDCA_BOARD_H

#include <stdint.h>

typedef struct
{
    uint32_t period;
    uint32_t high;
    uint32_t low;
    uint32_t frequency;
    uint32_t valid;
} ScopeMeasurement;

enum
{
    BOARD_SCOPE_AUTO = 0,
    BOARD_SCOPE_NORMAL = 1,
    BOARD_SCOPE_SINGLE = 2,
    BOARD_SCOPE_FREE = 3
};

void board_uart_putc( char value );
void board_uart_puts( const char * text );
int board_uart_try_getc( char * value );
void board_set_leds( uint16_t value );
void board_set_test_result( uint32_t value );
void board_display_decimal( uint32_t value );
void board_scope_measure( ScopeMeasurement * measurement );
uint32_t board_scope_measure_status( void );
void board_scope_set_average( uint32_t enabled );
void board_scope_set_live( uint32_t enabled, uint32_t hold );
void board_scope_set_mode( uint32_t mode );
void board_scope_set_edge( uint32_t falling );
void board_scope_set_timebase( uint32_t divider );
void board_capture_start( void );
void board_capture_cancel( void );
void board_scope_start_single( void );
uint32_t board_switches( void );
uint32_t board_button_events( void );
uint32_t board_capture_status( void );
uint32_t board_capture_sample_div( void );
uint32_t board_capture_active_div( void );
uint32_t board_capture_active_edge( void );
uint32_t board_capture_trigger_index( void );
uint32_t board_capture_sample( uint32_t index );
uint32_t board_perf_counter( uint32_t index );

#endif

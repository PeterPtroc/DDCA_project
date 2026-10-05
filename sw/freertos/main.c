#include <stdint.h>

#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"

#include "board.h"

#define TEST_PASS 0x600d600dUL
#define TEST_FAIL 0xdeaddeadUL
#define CAPTURE_EVENT_SINGLE ( 1UL << 0 )
#define CAPTURE_EVENT_DUMP   ( 1UL << 1 )
#define CAPTURE_EVENT_CANCEL ( 1UL << 2 )
#define CAPTURE_TRIGGER_TIMEOUT_MS 1000U

static QueueHandle_t measurement_queue;
static SemaphoreHandle_t uart_mutex;
static TaskHandle_t capture_task_handle;
static volatile uint32_t task_seen;
static volatile uint32_t context_switch_count;
static volatile uint32_t scope_hold;
static volatile uint32_t scope_timebase = 7U;
static volatile uint32_t scope_page;
static ScopeMeasurement capture_measurement;

static const uint32_t timebase_dividers[ 16 ] = {
    1U, 2U, 5U, 10U, 20U, 50U, 100U, 200U,
    500U, 1000U, 2000U, 5000U, 10000U, 20000U, 50000U, 100000U
};

static void mark_task_seen( uint32_t bit )
{
    taskENTER_CRITICAL();
    task_seen |= bit;
    context_switch_count++;
    taskEXIT_CRITICAL();
}

static uint32_t scope_duty_10000( uint32_t high, uint32_t period )
{
    uint32_t fraction = 0U;
    uint32_t bit;
    if( period == 0U )
    {
        return 0U;
    }
    for( bit = 0U; bit < 14U; bit++ )
    {
        high <<= 1;
        fraction <<= 1;
        if( high >= period )
        {
            high -= period;
            fraction |= 1U;
        }
    }
    return ( fraction * 10000U ) >> 14;
}

static void uart_put_u16_le( uint32_t value )
{
    board_uart_putc( ( char ) value );
    board_uart_putc( ( char ) ( value >> 8 ) );
}

static void uart_put_u32_le( uint32_t value )
{
    uart_put_u16_le( value );
    uart_put_u16_le( value >> 16 );
}

static void uart_send_status( void )
{
    board_uart_puts( "SCP2\n" );
}

static void uart_send_measurement( void )
{
    ScopeMeasurement measurement = { 0 };
    ( void ) xQueuePeek( measurement_queue, &measurement, 0 );
    board_uart_puts( "MEA2" );
    uart_put_u32_le( board_scope_measure_status() );
    uart_put_u32_le( measurement.frequency );
    uart_put_u32_le( measurement.period );
    uart_put_u32_le( measurement.high );
    uart_put_u32_le( measurement.low );
}

static void uart_send_performance( void )
{
    uint32_t index;
    board_uart_puts( "PRF2" );
    for( index = 0U; index < 9U; index++ )
    {
        uart_put_u32_le( board_perf_counter( index ) );
    }
}

static uint16_t crc16_byte( uint16_t crc, uint8_t value )
{
    uint32_t result;
    __asm__ volatile ( ".insn r 0x0b, 0, 0, %0, %1, %2"
                       : "=r" ( result )
                       : "r" ( ( uint32_t ) crc ), "r" ( ( uint32_t ) value ) );
    return ( uint16_t ) result;
}

static void uart_put_crc_byte( uint8_t value, uint16_t * crc )
{
    *crc = crc16_byte( *crc, value );
    board_uart_putc( ( char ) value );
}

static void uart_put_crc_u16( uint32_t value, uint16_t * crc )
{
    uart_put_crc_byte( ( uint8_t ) value, crc );
    uart_put_crc_byte( ( uint8_t ) ( value >> 8 ), crc );
}

static void uart_put_crc_u32( uint32_t value, uint16_t * crc )
{
    uart_put_crc_u16( value, crc );
    uart_put_crc_u16( value >> 16, crc );
}

static void capture_send_packet( void )
{
    uint16_t crc = 0xffffU;
    uint32_t byte_index;
    uint32_t bit_index;
    uint8_t packed;

    for( byte_index = 0U; byte_index < 4U; byte_index++ )
    {
        uart_put_crc_byte( ( uint8_t ) "CAP2"[ byte_index ], &crc );
    }
    uart_put_crc_byte( 2U, &crc );
    uart_put_crc_byte( ( uint8_t ) board_capture_active_edge(), &crc );
    uart_put_crc_u16( 4096U, &crc );
    uart_put_crc_u32( board_capture_active_div(), &crc );
    uart_put_crc_u16( board_capture_trigger_index(), &crc );
    uart_put_crc_u32( capture_measurement.period, &crc );
    uart_put_crc_u32( capture_measurement.high, &crc );
    uart_put_crc_u32( capture_measurement.frequency, &crc );

    for( byte_index = 0U; byte_index < 512U; byte_index++ )
    {
        packed = 0U;
        for( bit_index = 0U; bit_index < 8U; bit_index++ )
        {
            packed |= ( uint8_t ) ( board_capture_sample( byte_index * 8U + bit_index )
                                    << bit_index );
        }
        uart_put_crc_byte( packed, &crc );
    }
    uart_put_u16_le( crc );
}

static void measurement_task( void * argument )
{
    ScopeMeasurement measurement;
    ( void ) argument;
    for( ; ; )
    {
        board_scope_measure( &measurement );
        ( void ) xQueueOverwrite( measurement_queue, &measurement );
        mark_task_seen( 1U << 0 );
        vTaskDelay( pdMS_TO_TICKS( 20 ) );
    }
}

static void ui_task( void * argument )
{
    uint32_t previous_switches = 0xffffffffUL;
    uint32_t switches;
    uint32_t buttons;
    uint32_t heartbeat_divider = 0U;
    uint32_t page_limit;
    uint32_t display_value;
    uint16_t heartbeat = 1U;
    ScopeMeasurement measurement;
    ( void ) argument;

    board_scope_set_average( 0U );
    board_scope_set_timebase( timebase_dividers[ scope_timebase ] );
    board_scope_set_live( 1U, 0U );
    for( ; ; )
    {
        switches = board_switches();
        if( switches != previous_switches )
        {
            board_scope_set_edge( switches & 1U );
            board_scope_set_mode( ( switches >> 1 ) & 3U );
            board_scope_set_average( ( switches >> 12 ) & 1U );
            previous_switches = switches;
        }

        buttons = board_button_events();
        if( ( buttons & 1U ) != 0U )
        {
            if( ( ( switches >> 1 ) & 3U ) == BOARD_SCOPE_SINGLE )
            {
                ( void ) xTaskNotify( capture_task_handle, CAPTURE_EVENT_SINGLE, eSetBits );
            }
            else
            {
                scope_hold ^= 1U;
                board_scope_set_live( 1U, scope_hold );
            }
        }
        if( ( ( buttons & 2U ) != 0U ) && ( scope_timebase > 0U ) )
        {
            scope_timebase--;
            board_scope_set_timebase( timebase_dividers[ scope_timebase ] );
        }
        if( ( ( buttons & 16U ) != 0U ) && ( scope_timebase < 15U ) )
        {
            scope_timebase++;
            board_scope_set_timebase( timebase_dividers[ scope_timebase ] );
        }
        page_limit = ( ( switches >> 15 ) & 1U ) != 0U ? 15U : 6U;
        if( ( buttons & 4U ) != 0U )
        {
            scope_page = ( scope_page == 0U ) ? page_limit - 1U : scope_page - 1U;
        }
        if( ( buttons & 8U ) != 0U )
        {
            scope_page++;
            if( scope_page >= page_limit )
            {
                scope_page = 0U;
            }
        }

        heartbeat_divider++;
        if( heartbeat_divider >= 50U )
        {
            heartbeat_divider = 0U;
            heartbeat ^= 1U;
        }
        board_set_leds( heartbeat );
        if( xQueuePeek( measurement_queue, &measurement, 0 ) == pdPASS )
        {
            switch( scope_page )
            {
                case 0U: display_value = measurement.frequency; break;
                case 1U: display_value = measurement.period; break;
                case 2U: display_value = measurement.high; break;
                case 3U: display_value = measurement.low; break;
                case 4U: display_value = scope_duty_10000( measurement.high,
                                                           measurement.period ); break;
                case 5U: display_value = board_scope_measure_status(); break;
                default: display_value = board_perf_counter( scope_page - 6U ); break;
            }
            board_display_decimal( display_value );
        }
        mark_task_seen( 1U << 1 );
        vTaskDelay( pdMS_TO_TICKS( 10 ) );
    }
}

static void uart_task( void * argument )
{
    TickType_t telemetry_time = 0U;
    char command;
    ( void ) argument;

    ( void ) xSemaphoreTake( uart_mutex, portMAX_DELAY );
    board_uart_puts( "boot rv32i_zicsr FreeRTOS\r\n" );
    uart_send_status();
    ( void ) xSemaphoreGive( uart_mutex );

    for( ; ; )
    {
        // Drain the FIFO before sleeping; a byte arrives every 87 us at 115200.
        while( board_uart_try_getc( &command ) != 0 )
        {
            if( command == 'd' )
            {
                ( void ) xTaskNotify( capture_task_handle, CAPTURE_EVENT_DUMP, eSetBits );
            }
            else if( command == '1' )
            {
                ( void ) xTaskNotify( capture_task_handle, CAPTURE_EVENT_SINGLE, eSetBits );
            }
            else if( command == 'c' )
            {
                ( void ) xTaskNotify( capture_task_handle, CAPTURE_EVENT_CANCEL, eSetBits );
            }
            else
            {
                ( void ) xSemaphoreTake( uart_mutex, portMAX_DELAY );
                if( command == 's' )
                {
                    uart_send_status();
                }
                else if( command == 'm' )
                {
                    uart_send_measurement();
                }
                else if( command == 'p' )
                {
                    uart_send_performance();
                }
                else if( command == 'h' )
                {
                    scope_hold = 1U;
                    board_scope_set_live( 1U, 1U );
                }
                else if( command == 'r' )
                {
                    scope_hold = 0U;
                    board_scope_set_mode( ( board_switches() >> 1 ) & 3U );
                    board_scope_set_live( 1U, 0U );
                }
                ( void ) xSemaphoreGive( uart_mutex );
            }
        }

        if( ( ( board_switches() >> 13 ) & 1U ) != 0U &&
            ( xTaskGetTickCount() - telemetry_time ) >= pdMS_TO_TICKS( 100 ) )
        {
            telemetry_time = xTaskGetTickCount();
            ( void ) xSemaphoreTake( uart_mutex, portMAX_DELAY );
            uart_send_measurement();
            ( void ) xSemaphoreGive( uart_mutex );
        }
        mark_task_seen( 1U << 2 );
        vTaskDelay( pdMS_TO_TICKS( 1 ) );
    }
}

static void capture_task( void * argument )
{
    uint32_t events;
    uint32_t active = 0U;
    uint32_t dump_pending = 0U;
    TickType_t started = 0U;
    TickType_t timeout = 0U;
    const char * error;
    ( void ) argument;
    for( ; ; )
    {
        mark_task_seen( 1U << 3 );
        events = 0U;
        error = NULL;
        ( void ) xTaskNotifyWait( 0U, 0xffffffffUL, &events,
                                 pdMS_TO_TICKS( active != 0U ? 1U : 10U ) );
        if( ( events & CAPTURE_EVENT_CANCEL ) != 0U )
        {
            board_capture_cancel();
            active = 0U;
            dump_pending = 0U;
            error = "ERR2 CANCELLED\n";
        }
        else
        {
            if( ( events & CAPTURE_EVENT_SINGLE ) != 0U ||
                ( ( events & CAPTURE_EVENT_DUMP ) != 0U && active == 0U &&
                  ( board_capture_status() & 4U ) == 0U ) )
            {
                // UI writes cannot interleave this acquisition snapshot/arm.
                taskENTER_CRITICAL();
                board_scope_measure( &capture_measurement );
                if( ( events & CAPTURE_EVENT_SINGLE ) != 0U )
                {
                    board_scope_start_single();
                }
                else
                {
                    board_capture_start();
                }
                timeout = pdMS_TO_TICKS( CAPTURE_TRIGGER_TIMEOUT_MS +
                    ( 4096U * board_capture_active_div() + 99999U ) / 100000U );
                started = xTaskGetTickCount();
                active = 1U;
                taskEXIT_CRITICAL();
            }
            if( ( events & CAPTURE_EVENT_DUMP ) != 0U )
            {
                dump_pending = 1U;
            }
            if( ( board_capture_status() & 4U ) != 0U )
            {
                active = 0U;
                if( dump_pending != 0U )
                {
                    ( void ) xSemaphoreTake( uart_mutex, portMAX_DELAY );
                    capture_send_packet();
                    ( void ) xSemaphoreGive( uart_mutex );
                    dump_pending = 0U;
                }
            }
            else if( active != 0U && ( xTaskGetTickCount() - started ) >= timeout )
            {
                board_capture_cancel();
                active = 0U;
                dump_pending = 0U;
                error = "ERR2 TIMEOUT\n";
            }
        }
        if( error != NULL )
        {
            ( void ) xSemaphoreTake( uart_mutex, portMAX_DELAY );
            board_uart_puts( error );
            ( void ) xSemaphoreGive( uart_mutex );
        }
    }
}

int main( void )
{
    measurement_queue = xQueueCreate( 1, sizeof( ScopeMeasurement ) );
    uart_mutex = xSemaphoreCreateMutex();
    configASSERT( measurement_queue != NULL );
    configASSERT( uart_mutex != NULL );
    configASSERT( xTaskCreate( capture_task, "capture", 256, NULL, 2,
                              &capture_task_handle ) == pdPASS );
    configASSERT( xTaskCreate( measurement_task, "measure", 256, NULL, 2, NULL ) == pdPASS );
    configASSERT( xTaskCreate( ui_task, "ui", 256, NULL, 1, NULL ) == pdPASS );
    configASSERT( xTaskCreate( uart_task, "uart", 320, NULL, 3, NULL ) == pdPASS );
    vTaskStartScheduler();
    board_set_test_result( TEST_FAIL );
    for( ; ; )
    {
    }
}

void vApplicationIdleHook( void )
{
    if( ( task_seen == 0x0fU ) && ( xTaskGetTickCount() >= 2U ) &&
        ( context_switch_count >= 4U ) )
    {
        board_set_test_result( TEST_PASS );
    }
}

void vApplicationMallocFailedHook( void )
{
    board_set_test_result( 0xdead0002UL );
    for( ; ; )
    {
    }
}

void vApplicationStackOverflowHook( TaskHandle_t task, char * task_name )
{
    ( void ) task;
    ( void ) task_name;
    board_set_test_result( 0xdead0003UL );
    for( ; ; )
    {
    }
}

void vAssertCalled( const char * file, int line )
{
    ( void ) file;
    ( void ) line;
    board_set_test_result( 0xdead0004UL );
    for( ; ; )
    {
    }
}

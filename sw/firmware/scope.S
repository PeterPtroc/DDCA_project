# RV32 Real-Time Digital Scope v2.0 firmware.
# Dedicated RTL owns synchronization, edge timing, live frames, deep sampling,
# RGB status and seven-segment scanning.  The CPU is the non-blocking control
# plane except during an explicitly requested deep-capture dump.

        lui   s0, 0x40000       # GPIO / result
        lui   s1, 0x40001       # UART
        lui   s2, 0x40002       # Timer
        lui   s4, 0x40004       # Deep capture
        lui   s5, 0x40005       # Live scope
        lui   s6, 0x40006       # Performance counters
        lui   s7, 0x40007       # Buttons / switches
        lui   s8, 0x40008       # Seven segment
        lui   s9, 0x40009       # Edge meter
        lui   s10, 0x10000      # Firmware state RAM
        lui   sp, 0x10001       # top of 4 KiB data RAM

        sw    x0, 0(s10)        # page
        addi  t0, x0, 7
        sw    t0, 4(s10)        # timebase index: 2 us / LED
        sw    x0, 8(s10)        # RUN (not HOLD)
        addi  t0, x0, -1
        sw    t0, 12(s10)       # force initial switch update
        sw    x0, 16(s10)       # display deadline base
        sw    x0, 20(s10)       # telemetry deadline base
        sw    x0, 32(s10)       # cached frequency
        sw    x0, 36(s10)       # cached period
        sw    x0, 40(s10)       # cached high
        sw    x0, 44(s10)       # cached low
        li    t0, -100000000
        sw    t0, 48(s10)       # timebase pop-up start (initially expired)

        # READY, display enabled.
        li    t0, 0x0e0a0d14
        sw    t0, 0(s8)
        li    t0, 0x1f1f1f13
        sw    t0, 4(s8)
        sw    x0, 8(s8)
        addi  t0, x0, 1
        sw    t0, 12(s8)

        # Edge meter enabled. Live scope starts after the first switch update.
        addi  t0, x0, 1
        sw    t0, 0(s9)
        call  apply_timebase
        call  update_switches
        call  apply_live_control
        call  send_status

main_loop:
        call  update_switches
        call  process_buttons
        call  service_single
        call  periodic_display
        call  check_uart
        call  service_telemetry
        j     main_loop

# Apply the meaningful scope controls when synchronized switch state changes.
update_switches:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    t0, 8(s7)
        lw    t1, 12(s10)
        beq   t0, t1, update_switches_done
        sw    t0, 12(s10)

        andi  t1, t0, 1        # trigger edge
        sw    t1, 12(s5)
        sw    t1, 8(s4)
        srli  t1, t0, 1        # trigger mode
        andi  t1, t1, 3
        sw    t1, 8(s5)
        srli  t1, t0, 12       # averaging -> EDGE CONTROL bit2
        andi  t1, t1, 1
        slli  t1, t1, 2
        ori   t1, t1, 1
        sw    t1, 0(s9)

update_switches_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

process_buttons:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    t0, 4(s7)        # clear-on-read event bits
        beq   t0, x0, process_buttons_done
        mv    t6, t0            # calls below may clobber t0

        andi  t1, t6, 1        # CENTER
        beq   t1, x0, button_left
        lw    t2, 12(s10)
        srli  t2, t2, 1
        andi  t2, t2, 3
        addi  t3, x0, 2
        bne   t2, t3, toggle_hold
        sw    x0, 8(s10)
        sw    x0, 0(s5)        # clear prior SINGLE state
        addi  t3, x0, 2
        sw    t3, 0(s4)        # clear deep capture
        addi  t3, x0, 1
        sw    t3, 0(s4)        # arm deep capture
        sw    t3, 0(s5)        # arm live scope
        j     button_left
toggle_hold:
        lw    t3, 8(s10)
        xori  t3, t3, 1
        sw    t3, 8(s10)
        call  apply_live_control

button_left:
        andi  t1, t6, 4
        beq   t1, x0, button_right
        lw    t2, 0(s10)
        addi  t2, t2, -1
        bge   t2, x0, store_page
        lw    t3, 12(s10)
        srli  t3, t3, 15
        andi  t3, t3, 1
        beq   t3, x0, normal_last_page
        addi  t2, x0, 8
        j     store_page
normal_last_page:
        addi  t2, x0, 5
store_page:
        sw    t2, 0(s10)

button_right:
        andi  t1, t6, 8
        beq   t1, x0, button_up
        lw    t2, 0(s10)
        addi  t2, t2, 1
        lw    t3, 12(s10)
        srli  t3, t3, 15
        andi  t3, t3, 1
        beq   t3, x0, normal_page_limit
        addi  t4, x0, 9
        j     check_page_limit
normal_page_limit:
        addi  t4, x0, 6
check_page_limit:
        blt   t2, t4, store_right_page
        addi  t2, x0, 0
store_right_page:
        sw    t2, 0(s10)

button_up:
        andi  t1, t6, 2
        beq   t1, x0, button_down
        lw    t2, 4(s10)
        beq   t2, x0, button_down
        addi  t2, t2, -1
        sw    t2, 4(s10)
        call  apply_timebase
        lw    t2, 0(s2)
        sw    t2, 48(s10)
button_down:
        andi  t1, t6, 16
        beq   t1, x0, process_buttons_done
        lw    t2, 4(s10)
        addi  t3, x0, 15
        bge   t2, t3, process_buttons_done
        addi  t2, t2, 1
        sw    t2, 4(s10)
        call  apply_timebase
        lw    t2, 0(s2)
        sw    t2, 48(s10)
process_buttons_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

apply_live_control:
        lw    t0, 8(s10)
        slli  t0, t0, 1
        ori   t0, t0, 1
        sw    t0, 0(s5)
        ret

apply_timebase:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    a0, 4(s10)
        call  timebase_div
        sw    a0, 16(s5)
        sw    a0, 12(s4)
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

# SINGLE completion freezes numeric UI after the hardware publishes its frame.
service_single:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        # Read the active hardware mode rather than the physical switch cache.
        # This also lets the UART `single` command request a true one-shot.
        lw    t0, 8(s5)
        andi  t0, t0, 3
        addi  t1, x0, 2
        bne   t0, t1, service_single_done
        lw    t0, 4(s5)
        andi  t0, t0, 8
        beq   t0, x0, service_single_done
        lw    t0, 4(s4)
        andi  t0, t0, 4
        beq   t0, x0, service_single_done
        addi  t0, x0, 1
        sw    t0, 8(s10)
        call  apply_live_control
service_single_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

periodic_display:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    t0, 0(s2)
        lw    t1, 16(s10)
        sub   t2, t0, t1
        li    t3, 5000000      # 20 Hz
        bltu  t2, t3, periodic_display_done
        sw    t0, 16(s10)
        # A firmware-reported fatal result owns the display.  The RGB status
        # block uses the same 0xdeadxxxx convention.
        lw    t4, 12(s0)
        srli  t4, t4, 16
        li    t5, 0xdead
        beq   t4, t5, display_error
        # Deep-capture armed is the unambiguous SINGLE waiting state.  Merely
        # selecting SINGLE does not show Ar until CENTER (or UART `single`)
        # has actually armed the capture engines.
        lw    t4, 4(s4)
        andi  t4, t4, 1
        bne   t4, x0, display_armed
        lw    t1, 48(s10)
        sub   t2, t0, t1
        li    t3, 100000000     # show a changed timebase for one second
        bltu  t2, t3, display_timebase_popup
        lw    t0, 8(s10)
        bne   t0, x0, display_hold
        lw    t0, 0(s9)
        andi  t1, t0, 1
        beq   t1, x0, display_no_signal
        lw    t1, 16(s9)
        sw    t1, 32(s10)
        lw    t1, 4(s9)
        sw    t1, 36(s10)
        lw    t1, 8(s9)
        sw    t1, 40(s10)
        lw    t1, 12(s9)
        sw    t1, 44(s10)
display_cached:
        call  show_page
        j     periodic_display_done
display_no_signal:
        call  show_no_signal
        j     periodic_display_done
display_hold:
        call  show_hold
        j     periodic_display_done
display_armed:
        # Two right-most digits, read left-to-right as Ar.
        li    t0, 0x1f1f0a13
        j     display_state_text
display_error:
        # Three right-most digits, read left-to-right as Err.
        li    t0, 0x1f0e1313
display_state_text:
        sw    t0, 0(s8)
        li    t0, 0x1f1f1f1f
        sw    t0, 4(s8)
        sw    x0, 8(s8)
        j     periodic_display_done
display_timebase_popup:
        call  show_timebase
periodic_display_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

show_page:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    t0, 12(s10)
        srli  t0, t0, 15
        andi  t0, t0, 1
        bne   t0, x0, show_debug_page
        lw    t0, 0(s10)
        beq   t0, x0, show_frequency
        addi  t1, x0, 1
        beq   t0, t1, show_duty
        addi  t1, x0, 2
        beq   t0, t1, show_period
        addi  t1, x0, 3
        beq   t0, t1, show_high
        addi  t1, x0, 4
        beq   t0, t1, show_low
        call  show_timebase
        j     show_page_done
show_frequency:
        lw    a0, 32(s10)
        call  display_frequency
        j     show_page_done
show_duty:
        lw    a0, 40(s10)
        lw    a1, 36(s10)
        call  duty_10000
        addi  a1, x0, 13       # d
        call  display_decimal6
        addi  t0, x0, 4        # two fractional decimal digits
        sw    t0, 8(s8)
        j     show_page_done
show_period:
        lw    a0, 36(s10)
        addi  a1, x0, 17       # P
        call  display_time_ticks
        j     show_page_done
show_high:
        lw    a0, 40(s10)
        addi  a1, x0, 18       # H
        call  display_time_ticks
        j     show_page_done
show_low:
        lw    a0, 44(s10)
        addi  a1, x0, 21       # L
        call  display_time_ticks
        j     show_page_done

show_timebase:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    a0, 4(s10)
        call  timebase_div
        addi  a1, x0, 29       # t
        call  display_time_ticks
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

show_debug_page:
        lw    t0, 0(s10)
        slli  t0, t0, 2
        add   t0, s6, t0
        lw    a0, 0(t0)
        lw    t0, 0(s10)
        addi  a1, x0, 12       # default C
        beq   t0, x0, show_decimal
        addi  a1, x0, 18       # H-ish architecture counter label
show_decimal:
        call  display_decimal6
show_page_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

show_no_signal:
        # Approximate "no-SiG" using the extended seven-segment glyphs.
        li    t0, 0x1819161a
        sw    t0, 0(s8)
        li    t0, 0x1f1f1617
        sw    t0, 4(s8)
        sw    x0, 8(s8)
        ret

show_hold:
        # Four right-most digits, read left-to-right as HOLD.
        li    t0, 0x1200150d
        sw    t0, 0(s8)
        li    t0, 0x1f1f1f1f
        sw    t0, 4(s8)
        sw    x0, 8(s8)
        ret

# Frequency engineering display.  The six numeric digits are followed by a
# unit glyph, so values remain explicit instead of silently overflowing.
display_frequency:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        li    t0, 1000
        bltu  a0, t0, frequency_hz
        li    t0, 1000000
        bgeu  a0, t0, frequency_mhz
        call  divide100         # tenths of kHz
        addi  a1, x0, 15       # F
        addi  a2, x0, 28       # k
        addi  a3, x0, 4        # xxx.x
        call  display_with_unit
        j     frequency_done
frequency_mhz:
        call  divide100
        call  divide10          # thousandths of MHz
        addi  a1, x0, 15       # F
        addi  a2, x0, 27       # M
        addi  a3, x0, 16       # x.xxx
        call  display_with_unit
        j     frequency_done
frequency_hz:
        addi  a1, x0, 15       # F, base unit is Hz
        call  display_decimal6
        sw    x0, 8(s8)
frequency_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

# Convert 10 ns clock ticks to n/us/ms engineering units.
# a0=ticks, a1=measurement label.
display_time_ticks:
        addi  sp, sp, -8
        sw    ra, 4(sp)
        sw    a1, 0(sp)
        addi  t0, x0, 100
        bgeu  a0, t0, time_check_ms
        slli  t0, a0, 3
        slli  t1, a0, 1
        add   a0, t0, t1       # nanoseconds = ticks * 10
        lw    a1, 0(sp)
        addi  a2, x0, 22       # n
        addi  a3, x0, 0
        call  display_with_unit
        j     display_time_done
time_check_ms:
        li    t0, 100000
        bgeu  a0, t0, time_ms
        # One tick is 0.01 us, so the raw tick count is centi-microseconds.
        lw    a1, 0(sp)
        addi  a2, x0, 30       # u
        addi  a3, x0, 8        # xx.xx
        call  display_with_unit
        j     display_time_done
time_ms:
        call  divide100
        call  divide10          # centi-milliseconds
        lw    a1, 0(sp)
        addi  a2, x0, 27       # m/M approximation
        addi  a3, x0, 8        # xx.xx
        call  display_with_unit
display_time_done:
        lw    ra, 4(sp)
        addi  sp, sp, 8
        ret

# a0=value, a1=label, a2=unit glyph, a3=final decimal-point bitmap.
# Shift the six BCD digits left by one display position, put the unit at the
# right edge, and move the label to the left edge.
display_with_unit:
        addi  sp, sp, -12
        sw    ra, 8(sp)
        sw    a2, 4(sp)
        sw    a3, 0(sp)
        call  display_decimal6
        lw    t0, 0(s8)
        lw    t1, 4(s8)
        srli  t2, t0, 24
        slli  t0, t0, 8
        lw    t3, 4(sp)
        or    t0, t0, t3
        slli  t1, t1, 8
        or    t1, t1, t2
        sw    t0, 0(s8)
        sw    t1, 4(s8)
        lw    t0, 0(sp)
        sw    t0, 8(s8)
        lw    ra, 8(sp)
        addi  sp, sp, 12
        ret

# a0=value, a1=label glyph. Saturates instead of overflowing six digits.
display_decimal6:
        li    t6, 999999
        bltu  a0, t6, decimal_in_range
        beq   a0, t6, decimal_in_range
        mv    a0, t6
decimal_in_range:
        addi  t0, x0, 0        # packed BCD
        addi  t1, x0, 0        # bit count
bcd_outer:
        addi  t2, x0, 0
bcd_adjust:
        slli  t3, t2, 2
        srl   t4, t0, t3
        andi  t4, t4, 15
        addi  t5, x0, 5
        blt   t4, t5, bcd_no_add
        addi  t4, x0, 3
        sll   t4, t4, t3
        add   t0, t0, t4
bcd_no_add:
        addi  t2, t2, 1
        addi  t5, x0, 6
        blt   t2, t5, bcd_adjust
        slli  t0, t0, 1
        srli  t3, a0, 23
        andi  t3, t3, 1
        or    t0, t0, t3
        slli  a0, a0, 1
        addi  t1, t1, 1
        addi  t5, x0, 24
        blt   t1, t5, bcd_outer
        andi  t1, t0, 15
        srli  t2, t0, 4
        andi  t2, t2, 15
        slli  t2, t2, 8
        or    t1, t1, t2
        srli  t2, t0, 8
        andi  t2, t2, 15
        slli  t2, t2, 16
        or    t1, t1, t2
        srli  t2, t0, 12
        andi  t2, t2, 15
        slli  t2, t2, 24
        or    t1, t1, t2
        sw    t1, 0(s8)
        srli  t1, t0, 16
        andi  t1, t1, 15
        srli  t2, t0, 20
        andi  t2, t2, 15
        slli  t2, t2, 8
        or    t1, t1, t2
        slli  t2, a1, 16
        or    t1, t1, t2
        li    t2, 0x1f000000
        or    t1, t1, t2
        sw    t1, 4(s8)
        sw    x0, 8(s8)
        ret

check_uart:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    t0, 4(s1)
        andi  t0, t0, 2
        beq   t0, x0, check_uart_done
        lw    t0, 8(s1)
        andi  t0, t0, 255
        addi  t1, x0, 115      # s status
        beq   t0, t1, uart_status_command
        addi  t1, x0, 109      # m measure
        beq   t0, t1, uart_measure_command
        addi  t1, x0, 114      # r run
        beq   t0, t1, uart_run_command
        addi  t1, x0, 104      # h hold
        beq   t0, t1, uart_hold_command
        addi  t1, x0, 49       # 1 single
        beq   t0, t1, uart_single_command
        addi  t1, x0, 100      # d dump
        beq   t0, t1, uart_dump_command
        addi  t1, x0, 112      # p perf
        beq   t0, t1, uart_perf_command
        j     check_uart_done
uart_status_command:
        call  send_status
        j     check_uart_done
uart_measure_command:
        call  send_measurement
        j     check_uart_done
uart_run_command:
        # A UART one-shot temporarily forces MODE_SINGLE.  RUN returns to the
        # trigger mode selected by SW[2:1] before releasing HOLD.
        lw    t0, 12(s10)
        srli  t0, t0, 1
        andi  t0, t0, 3
        sw    t0, 8(s5)
        sw    x0, 8(s10)
        call  apply_live_control
        j     check_uart_done
uart_hold_command:
        addi  t0, x0, 1
        sw    t0, 8(s10)
        call  apply_live_control
        j     check_uart_done
uart_single_command:
        sw    x0, 8(s10)
        sw    x0, 0(s5)
        addi  t0, x0, 2
        sw    t0, 8(s5)        # force MODE_SINGLE for a real UART one-shot
        sw    t0, 0(s4)
        addi  t0, x0, 1
        sw    t0, 0(s4)
        sw    t0, 0(s5)
        j     check_uart_done
uart_dump_command:
        call  send_dump
        j     check_uart_done
uart_perf_command:
        call  send_perf
check_uart_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

service_telemetry:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    t0, 12(s10)
        srli  t0, t0, 13
        andi  t0, t0, 1
        beq   t0, x0, telemetry_done
        lw    t0, 0(s2)
        lw    t1, 20(s10)
        sub   t2, t0, t1
        li    t3, 10000000     # 100 ms
        bltu  t2, t3, telemetry_done
        sw    t0, 20(s10)
        call  send_measurement
telemetry_done:
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

uart_putc:
        lw    t0, 4(s1)
        andi  t0, t0, 1
        beq   t0, x0, uart_putc
        sw    a0, 0(s1)
        ret

send_status:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        addi  a0, x0, 83       # SCP2\n
        call  uart_putc
        addi  a0, x0, 67
        call  uart_putc
        addi  a0, x0, 80
        call  uart_putc
        addi  a0, x0, 50
        call  uart_putc
status_newline:
        addi  a0, x0, 10
        call  uart_putc
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

send_measurement:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        addi  a0, x0, 77       # MEA2
        call  uart_putc
        addi  a0, x0, 69
        call  uart_putc
        addi  a0, x0, 65
        call  uart_putc
        addi  a0, x0, 50
        call  uart_putc
        lw    a0, 0(s9)
        call  send_word
        lw    a0, 16(s9)
        call  send_word
        lw    a0, 4(s9)
        call  send_word
        lw    a0, 8(s9)
        call  send_word
        lw    a0, 12(s9)
        call  send_word
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

send_perf:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        addi  a0, x0, 80       # PRF2
        call  uart_putc
        addi  a0, x0, 82
        call  uart_putc
        addi  a0, x0, 70
        call  uart_putc
        addi  a0, x0, 50
        call  uart_putc
        addi  t1, x0, 0
perf_send_loop:
        slli  t2, t1, 2
        add   t2, s6, t2
        lw    a0, 0(t2)
        call  send_word
        addi  t1, t1, 1
        addi  t2, x0, 9
        blt   t1, t2, perf_send_loop
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

send_word:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        mv    t2, a0
        andi  a0, t2, 255
        call  uart_putc
        srli  t2, t2, 8
        andi  a0, t2, 255
        call  uart_putc
        srli  t2, t2, 8
        andi  a0, t2, 255
        call  uart_putc
        srli  t2, t2, 8
        andi  a0, t2, 255
        call  uart_putc
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

# CAP2 packet: magic, version, flags, count, sample_div, trigger_index,
# period, high, frequency, 512 packed bytes, CRC16/MODBUS little endian.
send_dump:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        lw    t0, 4(s4)
        andi  t0, t0, 4
        bne   t0, x0, dump_ready
        addi  t0, x0, 2
        sw    t0, 0(s4)
        addi  t0, x0, 1
        sw    t0, 0(s4)
dump_wait:
        lw    t0, 4(s4)
        andi  t0, t0, 4
        beq   t0, x0, dump_wait
dump_ready:
        addi  s11, x0, -1      # CRC initial value 0xffff
        addi  a0, x0, 67       # CAP2
        call  uart_crc_putc
        addi  a0, x0, 65
        call  uart_crc_putc
        addi  a0, x0, 80
        call  uart_crc_putc
        addi  a0, x0, 50
        call  uart_crc_putc
        addi  a0, x0, 2        # version
        call  uart_crc_putc
        lw    a0, 8(s4)        # flags bit0 = falling edge
        andi  a0, a0, 1
        call  uart_crc_putc
        addi  a0, x0, 0        # count 4096 = 0x1000 LE
        call  uart_crc_putc
        addi  a0, x0, 16
        call  uart_crc_putc
        lw    a0, 12(s4)
        call  send_word_crc
        lw    a0, 24(s4)
        call  send_half_crc
        lw    a0, 4(s9)
        call  send_word_crc
        lw    a0, 8(s9)
        call  send_word_crc
        lw    a0, 16(s9)
        call  send_word_crc

        addi  t2, x0, 0        # packed byte index
dump_byte_loop:
        slli  t3, t2, 3        # first sample index
        addi  t4, x0, 0        # bit index
        addi  t5, x0, 0        # packed byte
dump_bit_loop:
        slli  t6, t3, 2
        lui   a1, 0x40010
        add   t6, a1, t6
        lw    a0, 0(t6)
        andi  a0, a0, 1
        sll   a0, a0, t4
        or    t5, t5, a0
        addi  t3, t3, 1
        addi  t4, t4, 1
        addi  t6, x0, 8
        blt   t4, t6, dump_bit_loop
        mv    a0, t5
        call  uart_crc_putc
        addi  t2, t2, 1
        li    t3, 512
        blt   t2, t3, dump_byte_loop

        andi  a0, s11, 255
        call  uart_putc
        srli  a0, s11, 8
        andi  a0, a0, 255
        call  uart_putc
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

uart_crc_putc:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        crc16.b s11, s11, a0
        call  uart_putc
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

send_half_crc:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        mv    t2, a0
        andi  a0, t2, 255
        call  uart_crc_putc
        srli  t2, t2, 8
        andi  a0, t2, 255
        call  uart_crc_putc
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

send_word_crc:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        mv    t2, a0
        andi  a0, t2, 255
        call  uart_crc_putc
        srli  t2, t2, 8
        andi  a0, t2, 255
        call  uart_crc_putc
        srli  t2, t2, 8
        andi  a0, t2, 255
        call  uart_crc_putc
        srli  t2, t2, 8
        andi  a0, t2, 255
        call  uart_crc_putc
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

# floor(high / period * 10000), using a Q14 fractional divide.
duty_10000:
        addi  sp, sp, -4
        sw    ra, 0(sp)
        beq   a1, x0, duty_zero
        mv    t0, a0
        mv    t1, a1
        addi  t2, x0, 0
        addi  t3, x0, 14
duty_fraction_loop:
        slli  t0, t0, 1
        slli  t2, t2, 1
        bltu  t0, t1, duty_fraction_next
        sub   t0, t0, t1
        ori   t2, t2, 1
duty_fraction_next:
        addi  t3, t3, -1
        bne   t3, x0, duty_fraction_loop
        mv    a0, t2
        li    a1, 10000
        call  multiply32
        srli  a0, a0, 14
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret
duty_zero:
        addi  a0, x0, 0
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

# a0 * a1 -> a0 (inputs used here are guaranteed to fit in 32 bits).
multiply32:
        addi  t0, x0, 0
multiply_loop:
        beq   a1, x0, multiply_done
        andi  t1, a1, 1
        beq   t1, x0, multiply_skip
        add   t0, t0, a0
multiply_skip:
        slli  a0, a0, 1
        srli  a1, a1, 1
        j     multiply_loop
multiply_done:
        mv    a0, t0
        ret

# Unsigned divide by 100: a0=quotient, a1=remainder.
divide100:
        mv    t3, a0
        addi  t0, x0, 0
        addi  t1, x0, 0
        addi  t2, x0, 32
divide100_loop:
        slli  t1, t1, 1
        srli  t4, t3, 31
        or    t1, t1, t4
        slli  t3, t3, 1
        slli  t0, t0, 1
        addi  t4, x0, 100
        bltu  t1, t4, divide100_next
        sub   t1, t1, t4
        ori   t0, t0, 1
divide100_next:
        addi  t2, t2, -1
        bne   t2, x0, divide100_loop
        mv    a0, t0
        mv    a1, t1
        ret

# Unsigned divide by 10: a0=quotient, a1=remainder.
divide10:
        mv    t3, a0
        addi  t0, x0, 0
        addi  t1, x0, 0
        addi  t2, x0, 32
divide10_loop:
        slli  t1, t1, 1
        srli  t4, t3, 31
        or    t1, t1, t4
        slli  t3, t3, 1
        slli  t0, t0, 1
        addi  t4, x0, 10
        bltu  t1, t4, divide10_next
        sub   t1, t1, t4
        ori   t0, t0, 1
divide10_next:
        addi  t2, t2, -1
        bne   t2, x0, divide10_loop
        mv    a0, t0
        mv    a1, t1
        ret

timebase_div:
        beq   a0, x0, timebase_0
        addi  t0, x0, 1
        beq   a0, t0, timebase_1
        addi  t0, x0, 2
        beq   a0, t0, timebase_2
        addi  t0, x0, 3
        beq   a0, t0, timebase_3
        addi  t0, x0, 4
        beq   a0, t0, timebase_4
        addi  t0, x0, 5
        beq   a0, t0, timebase_5
        addi  t0, x0, 6
        beq   a0, t0, timebase_6
        addi  t0, x0, 7
        beq   a0, t0, timebase_7
        addi  t0, x0, 8
        beq   a0, t0, timebase_8
        addi  t0, x0, 9
        beq   a0, t0, timebase_9
        addi  t0, x0, 10
        beq   a0, t0, timebase_10
        addi  t0, x0, 11
        beq   a0, t0, timebase_11
        addi  t0, x0, 12
        beq   a0, t0, timebase_12
        addi  t0, x0, 13
        beq   a0, t0, timebase_13
        addi  t0, x0, 14
        beq   a0, t0, timebase_14
        li    a0, 100000
        ret
timebase_0:
        addi  a0, x0, 1
        ret
timebase_1:
        addi  a0, x0, 2
        ret
timebase_2:
        addi  a0, x0, 5
        ret
timebase_3:
        addi  a0, x0, 10
        ret
timebase_4:
        addi  a0, x0, 20
        ret
timebase_5:
        addi  a0, x0, 50
        ret
timebase_6:
        addi  a0, x0, 100
        ret
timebase_7:
        addi  a0, x0, 200
        ret
timebase_8:
        addi  a0, x0, 500
        ret
timebase_9:
        addi  a0, x0, 1000
        ret
timebase_10:
        addi  a0, x0, 2000
        ret
timebase_11:
        li    a0, 5000
        ret
timebase_12:
        li    a0, 10000
        ret
timebase_13:
        li    a0, 20000
        ret
timebase_14:
        li    a0, 50000
        ret

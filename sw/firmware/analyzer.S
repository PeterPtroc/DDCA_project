# RV32 Digital Analyzer v1.0 firmware.
# The CPU performs multi-period analysis; hardware owns sampling, edge timing,
# display refresh, and waveform rendering.

        lui   s0, 0x40000       # GPIO / result
        lui   s1, 0x40001       # UART
        lui   s2, 0x40004       # Capture control
        lui   s3, 0x40010       # Capture data window
        lui   s4, 0x40007       # Buttons and switches
        lui   s5, 0x40008       # Seven segment
        lui   s6, 0x40009       # Edge meter
        lui   s7, 0x4000a       # Pattern generator
        lui   s8, 0x40006       # Performance counters
        lui   s9, 0x10000       # Scratch RAM
        lui   sp, 0x10001       # top of 4 KiB data RAM
        addi  s10, x0, 0        # UI page
        addi  s11, x0, 0        # UART parser state

        # READY on the display (codes R=0x13 and Y=0x14).
        li    t0, 0x0e0a0d14
        sw    t0, 0(s5)
        li    t0, 0x1f1f1f13
        sw    t0, 4(s5)
        addi  t0, x0, 0
        sw    t0, 8(s5)
        addi  t0, x0, 1
        sw    t0, 12(s5)

        # Eight-channel self-test pattern. CH0 is 390625 Hz, about 30% duty.
        addi  t0, x0, 0
        sw    t0, 0(s7)
        addi  t0, x0, 7
        sw    t0, 4(s7)
        addi  t0, x0, 256
        sw    t0, 8(s7)
        addi  t0, x0, 77
        sw    t0, 12(s7)
        li    t0, 0x000000f8
        sw    t0, 16(s7)
        addi  t0, x0, 255
        sw    t0, 0(s7)

        # Capture defaults: CH0 rising, 100 MHz, 4096 samples, 2048 pretrigger.
        addi  t0, x0, 0
        sw    t0, 8(s2)
        sw    t0, 12(s2)
        addi  t0, x0, 1
        sw    t0, 28(s2)
        li    t0, 4096
        sw    t0, 16(s2)
        li    t0, 2048
        sw    t0, 32(s2)
        addi  t0, x0, 1
        sw    t0, 0(s6)         # enable edge meter, CH0

        call  send_status
        call  arm_capture

main_loop:
        # A completed capture is analyzed once. Four complete cycles are
        # averaged, rather than trusting a single transition pair.
        lw    t0, 4(s2)
        andi  t0, t0, 4
        beq   t0, x0, check_buttons
        lw    t1, 12(s9)
        bne   t1, x0, check_buttons
        call  analyze_capture
        addi  t1, x0, 1
        sw    t1, 12(s9)
        call  show_page
        lui   t0, 0x600d6
        addi  t0, t0, 13
        sw    t0, 12(s0)

check_buttons:
        lw    t0, 4(s4)         # clear-on-read events
        andi  t1, t0, 1         # CENTER: capture
        beq   t1, x0, button_left
        call  arm_capture
button_left:
        andi  t1, t0, 4
        beq   t1, x0, button_right
        addi  s10, s10, -1
        bge   s10, x0, button_show
        addi  s10, x0, 5
button_right:
        andi  t1, t0, 8
        beq   t1, x0, button_up
        addi  s10, s10, 1
        addi  t2, x0, 6
        blt   s10, t2, button_show
        addi  s10, x0, 0
button_show:
        call  show_page
button_up:
        andi  t1, t0, 2         # UP: faster sample rate
        beq   t1, x0, button_down
        lw    t2, 28(s2)
        srli  t2, t2, 1
        bne   t2, x0, write_rate
        addi  t2, x0, 1
write_rate:
        sw    t2, 28(s2)
button_down:
        andi  t1, t0, 16        # DOWN: slower sample rate
        beq   t1, x0, check_uart
        lw    t2, 28(s2)
        slli  t2, t2, 1
        sw    t2, 28(s2)

check_uart:
        lw    t0, 4(s1)
        andi  t0, t0, 2
        beq   t0, x0, main_loop
        lw    t0, 8(s1)
        andi  t0, t0, 255
        bne   s11, x0, command_channel_value
        addi  t1, x0, 115       # s: status
        beq   t0, t1, command_status
        addi  t1, x0, 97        # a: arm
        beq   t0, t1, command_arm
        addi  t1, x0, 109       # m: measure
        beq   t0, t1, command_measure
        addi  t1, x0, 100       # d: dump
        beq   t0, t1, command_dump
        addi  t1, x0, 99        # cN: channel
        beq   t0, t1, command_channel
        addi  t1, x0, 114       # r: rising
        beq   t0, t1, command_rising
        addi  t1, x0, 102       # f: falling
        beq   t0, t1, command_falling
        addi  t1, x0, 49        # rate codes
        beq   t0, t1, rate_100m
        addi  t1, x0, 53
        beq   t0, t1, rate_50m
        addi  t1, x0, 54
        beq   t0, t1, rate_25m
        addi  t1, x0, 50
        beq   t0, t1, rate_10m
        addi  t1, x0, 51
        beq   t0, t1, rate_1m
        addi  t1, x0, 52
        beq   t0, t1, rate_100k
        j     main_loop

command_status:
        call  send_status
        j     main_loop
command_arm:
        call  arm_capture
        j     main_loop
command_measure:
        call  send_measurement
        j     main_loop
command_dump:
        call  send_dump
        j     main_loop
command_channel:
        addi  s11, x0, 1
        j     main_loop
command_channel_value:
        addi  s11, x0, 0
        addi  t0, t0, -48
        andi  t0, t0, 7
        sw    t0, 8(s2)
        slli  t0, t0, 8
        ori   t0, t0, 1
        sw    t0, 0(s6)
        j     main_loop
command_rising:
        sw    x0, 12(s2)
        j     main_loop
command_falling:
        addi  t0, x0, 1
        sw    t0, 12(s2)
        j     main_loop
rate_100m:
        addi  t0, x0, 1
        j     command_rate
rate_50m:
        addi  t0, x0, 2
        j     command_rate
rate_25m:
        addi  t0, x0, 4
        j     command_rate
rate_10m:
        addi  t0, x0, 10
        j     command_rate
rate_1m:
        addi  t0, x0, 100
        j     command_rate
rate_100k:
        addi  t0, x0, 1000
command_rate:
        sw    t0, 28(s2)
        j     main_loop

arm_capture:
        addi  t0, x0, 2
        sw    t0, 0(s2)
        sw    x0, 12(s9)
        addi  t0, x0, 1
        sw    t0, 0(s2)
        ret

analyze_capture:
        addi  t0, x0, 0         # sample index
        lw    t1, 0(s3)
        andi  t1, t1, 1         # previous value
        addi  t2, x0, -1        # previous rising index
        addi  t3, x0, -1        # high interval start
        addi  t4, x0, 0         # period sum
        addi  t5, x0, 0         # high sum
        addi  t6, x0, 0         # complete cycles
analyze_loop:
        addi  t0, t0, 1
        slli  a0, t0, 2
        add   a0, s3, a0
        lw    a1, 0(a0)
        andi  a1, a1, 1
        beq   a1, t1, analyze_next
        beq   a1, x0, analyze_fall
        blt   t2, x0, analyze_first_rise
        sub   a2, t0, t2
        add   t4, t4, a2
        addi  t6, t6, 1
        addi  a3, x0, 4
        bge   t6, a3, analyze_done
analyze_first_rise:
        mv    t2, t0
        mv    t3, t0
        j     analyze_next
analyze_fall:
        blt   t3, x0, analyze_next
        sub   a2, t0, t3
        add   t5, t5, a2
analyze_next:
        mv    t1, a1
        li    a2, 4095
        blt   t0, a2, analyze_loop
analyze_done:
        srli  t4, t4, 2         # average across four periods
        srli  t5, t5, 2
        sw    t4, 0(s9)
        sw    t5, 4(s9)
        lw    a0, 12(s6)        # precise edge-meter frequency
        sw    a0, 8(s9)
        ret

show_page:
        beq   s10, x0, page_frequency
        addi  t0, x0, 1
        beq   s10, t0, page_duty
        addi  t0, x0, 2
        beq   s10, t0, page_period
        addi  t0, x0, 3
        beq   s10, t0, page_high
        addi  t0, x0, 4
        beq   s10, t0, page_count
        lw    a0, 8(s8)
        addi  a1, x0, 5         # S
        j     display_decimal6
page_frequency:
        lw    a0, 8(s9)
        addi  a1, x0, 15        # F
        j     display_decimal6
page_duty:
        lw    t0, 4(s9)
        lw    t1, 0(s9)
        slli  a0, t0, 6
        slli  t2, t0, 5
        add   a0, a0, t2
        slli  t2, t0, 2
        add   a0, a0, t2        # high * 100
        addi  t2, x0, 0
duty_divide:
        blt   a0, t1, duty_done
        sub   a0, a0, t1
        addi  t2, t2, 1
        j     duty_divide
duty_done:
        mv    a0, t2
        addi  a1, x0, 13        # d
        j     display_decimal6
page_period:
        lw    a0, 0(s9)
        addi  a1, x0, 17        # P
        j     display_decimal6
page_high:
        lw    a0, 4(s9)
        addi  a1, x0, 18        # H
        j     display_decimal6
page_count:
        lw    a0, 20(s2)
        addi  a1, x0, 12        # C

# Convert low 24 bits to six packed BCD digits using double dabble.
display_decimal6:
        addi  t0, x0, 0         # BCD
        addi  t1, x0, 0         # bit count
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
        sw    t1, 0(s5)
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
        sw    t1, 4(s5)
        ret

uart_putc:
        lw    t0, 4(s1)
        andi  t0, t0, 1
        beq   t0, x0, uart_putc
        sw    a0, 0(s1)
        ret

send_status:
        addi sp,sp,-4
        sw   ra,0(sp)
        addi a0,x0,82
        call uart_putc
        addi a0,x0,86
        call uart_putc
        addi a0,x0,51
        call uart_putc
        addi a0,x0,50
        call uart_putc
        addi a0,x0,32
        call uart_putc
        addi a0,x0,65
        call uart_putc
        addi a0,x0,78
        call uart_putc
        addi a0,x0,65
        call uart_putc
        addi a0,x0,76
        call uart_putc
        addi a0,x0,89
        call uart_putc
        addi a0,x0,90
        call uart_putc
        addi a0,x0,69
        call uart_putc
        addi a0,x0,82
        call uart_putc
        addi a0,x0,32
        call uart_putc
        addi a0,x0,82
        call uart_putc
        addi a0,x0,69
        call uart_putc
        addi a0,x0,65
        call uart_putc
        addi a0,x0,68
        call uart_putc
        addi a0,x0,89
        call uart_putc
        addi a0,x0,10
        call uart_putc
        lw   ra,0(sp)
        addi sp,sp,4
        ret

send_measurement:
        addi sp,sp,-4
        sw   ra,0(sp)
        addi a0,x0,77
        call uart_putc
        addi a0,x0,69
        call uart_putc
        addi a0,x0,65
        call uart_putc
        addi a0,x0,48
        call uart_putc
        lw    a0, 12(s6)
        call  send_word
        lw    a0, 4(s6)
        call  send_word
        lw    a0, 8(s6)
        call  send_word
        lw    ra,0(sp)
        addi  sp,sp,4
        ret

send_word:
        addi  sp,sp,-4
        sw    ra,0(sp)
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
        lw    ra,0(sp)
        addi  sp,sp,4
        ret

send_dump:
        addi sp,sp,-4
        sw   ra,0(sp)
        addi a0,x0,67
        call uart_putc
        addi a0,x0,65
        call uart_putc
        addi a0,x0,80
        call uart_putc
        addi a0,x0,48
        call uart_putc
        addi a0,x0,0          # uint16 count = 0x1000
        call uart_putc
        addi a0,x0,16
        call uart_putc
        addi t2,x0,0
dump_loop:
        slli  t3,t2,2
        add   t3,s3,t3
        lw    a0,0(t3)
        andi  a0,a0,255
        call  uart_putc
        addi  t2,t2,1
        li    t3,4096
        blt   t2,t3,dump_loop
        lw    ra,0(sp)
        addi  sp,sp,4
        ret

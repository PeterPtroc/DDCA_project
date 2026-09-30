# End-to-end bring-up image.
# The image does not publish PASS until CRC, PWM, Capture, and UART checks pass.

        # CRC-16/MODBUS("123456789", init=0xffff) == 0x4b37.
        addi  s5, x0, -1
        addi  s6, x0, 0x31
        crc16.b s5, s5, s6
        addi  s6, x0, 0x32
        crc16.b s5, s5, s6
        addi  s6, x0, 0x33
        crc16.b s5, s5, s6
        addi  s6, x0, 0x34
        crc16.b s5, s5, s6
        addi  s6, x0, 0x35
        crc16.b s5, s5, s6
        addi  s6, x0, 0x36
        crc16.b s5, s5, s6
        addi  s6, x0, 0x37
        crc16.b s5, s5, s6
        addi  s6, x0, 0x38
        crc16.b s5, s5, s6
        addi  s6, x0, 0x39
        crc16.b s5, s5, s6
        lui   s7, 0x5
        addi  s7, s7, -1225
        bne   s5, s7, fail

        lui   s0, 0x40000       # GPIO
        lui   s1, 0x40001       # UART
        lui   s2, 0x40003       # PWM
        lui   s3, 0x40004       # Capture control
        lui   s4, 0x40010       # Capture data window

        # Configure a short 50% duty PWM: period=8, high=4.
        addi  t0, x0, 0
        sw    t0, 0(s2)
        addi  t0, x0, 8
        sw    t0, 4(s2)
        addi  t0, x0, 4
        sw    t0, 8(s2)

        # Capture 32 samples on channel 0, rising-edge trigger.
        addi  t0, x0, 0
        sw    t0, 12(s3)
        sw    t0, 8(s3)
        addi  t0, x0, 32
        sw    t0, 16(s3)
        addi  t0, x0, 1
        sw    t0, 0(s3)

        # Start PWM after Capture is armed.
        sw    t0, 0(s2)

wait_capture:
        lw    t1, 4(s3)
        andi  t1, t1, 4
        beq   t1, x0, wait_capture

        # Count high samples and transitions in the captured window.
        addi  t0, x0, 0
        addi  t1, x0, 0
        addi  t2, x0, 0
        lw    t3, 0(s4)
        andi  t3, t3, 1
        mv    t4, t3
        beq   t3, x0, scan_first_done
        addi  t1, t1, 1
scan_first_done:
        addi  t0, x0, 1
scan_loop:
        slli  t5, t0, 2
        add   t5, s4, t5
        lw    t6, 0(t5)
        andi  t6, t6, 1
        beq   t6, x0, scan_no_high
        addi  t1, t1, 1
scan_no_high:
        beq   t6, t4, scan_same
        addi  t2, t2, 1
scan_same:
        mv    t4, t6
        addi  t0, t0, 1
        addi  t5, x0, 32
        blt   t0, t5, scan_loop

        addi  t5, x0, 16
        bne   t1, t5, fail
        addi  t5, x0, 7
        bne   t2, t5, fail

        # Exercise UART STATUS before publishing PASS.
uart_wait:
        lw    t0, 4(s1)
        andi  t0, t0, 1
        beq   t0, x0, uart_wait
        addi  t0, x0, 0x50
        sw    t0, 0(s1)

uart_wait_busy:
        lw    t0, 4(s1)
        andi  t0, t0, 1
        bne   t0, x0, uart_wait_busy
uart_wait_done:
        lw    t0, 4(s1)
        andi  t0, t0, 1
        beq   t0, x0, uart_wait_done

        lui   t0, 0x600d6
        addi  t0, t0, 13
        sw    t0, 12(s0)
pass_loop:
        j     pass_loop

fail:
        lui   t0, 0x40000
        lui   t1, 0xdead0
        sw    t1, 12(t0)
fail_loop:
        j     fail_loop

# CRC-16/MODBUS known vector: "123456789" from 0xffff -> 0x4b37.
        addi  s0, x0, -1
        addi  s1, x0, 0x31
        crc16.b s0, s0, s1
        addi  s1, x0, 0x32
        crc16.b s0, s0, s1
        addi  s1, x0, 0x33
        crc16.b s0, s0, s1
        addi  s1, x0, 0x34
        crc16.b s0, s0, s1
        addi  s1, x0, 0x35
        crc16.b s0, s0, s1
        addi  s1, x0, 0x36
        crc16.b s0, s0, s1
        addi  s1, x0, 0x37
        crc16.b s0, s0, s1
        addi  s1, x0, 0x38
        crc16.b s0, s0, s1
        addi  s1, x0, 0x39
        crc16.b s0, s0, s1
        lui   s1, 0x5
        addi  s1, s1, -1225
        bne   s0, s1, fail
        lui   t0, 0x40000
        lui   t1, 0x600d6
        addi  t1, t1, 13
        sw    t1, 12(t0)
done:   j     done
fail:
        lui   t0, 0x40000
        lui   t1, 0xdead0
        sw    t1, 12(t0)
fail_loop: j fail_loop

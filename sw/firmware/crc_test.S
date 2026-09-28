        addi t0, x0, -1
        addi t1, x0, 0x31
        crc16.b t0, t0, t1
        jal x0, .

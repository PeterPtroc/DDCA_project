        addi x1, x0, 1
        addi x2, x0, -1
        add x3, x1, x2
        lui t0, 0x40000
        lui t1, 0x600d6
        addi t1, t1, 0x00d
        sw t1, 12(t0)
        jal x0, .

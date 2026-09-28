        lui t0, 0x10000
        addi t1, x0, 3
        addi t2, x0, 4
        add t3, t1, t2
        sub t4, t3, t1
        sw t4, 0(t0)
        lw t5, 0(t0)
        add t6, t5, t1
        jal x0, .

# Load-use and forwarding check. The dependent result must be 8.
        lui   t0, 0x10000
        addi  t1, x0, 3
        sw    t1, 0(t0)
        lw    t2, 0(t0)
        addi  t3, t2, 4
        addi  t4, t3, 1
        addi  t5, x0, 8
        bne   t4, t5, fail
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

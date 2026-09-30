# Minimal arithmetic/branch check. PASS is written only after the result matches.
        addi  t0, x0, 1
        addi  t1, x0, -1
        add   t2, t0, t1
        bne   t2, x0, fail
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

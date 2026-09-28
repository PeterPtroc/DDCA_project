# Minimal bring-up image. The full analyzer firmware can be assembled with the
# same tool once the board-specific application policy is finalized.
        lui   sp, 0x10001
        addi  sp, sp, 0
        lui   t0, 0x40000
        lui   t1, 0x600d6
        addi  t1, t1, 0x00d
        sw    t1, 12(t0)
idle:   jal   x0, idle

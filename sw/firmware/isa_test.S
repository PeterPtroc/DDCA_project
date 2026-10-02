# Directed architectural test for every implemented CPU instruction.
# s11 holds the failing case number; PASS is published only after all groups.

        # Arithmetic boundaries and LUI.
        li    s11, 1
        li    t0, 0x7fffffff
        addi  t1, x0, 1
        add   t2, t0, t1
        li    t3, 0x80000000
        bne   t2, t3, fail
        addi  t0, x0, -1
        add   t2, t0, t1
        bne   t2, x0, fail
        sub   t2, x0, t1
        bne   t2, t0, fail
        lui   t2, 0x12345
        li    t3, 0x12345000
        bne   t2, t3, fail
        addi  x0, x0, 1
        bne   x0, x0, fail

        # R-type and I-type logical operations.
        li    s11, 2
        li    t0, 0x0f0f0f0f
        li    t1, 0x00ff00ff
        and   t2, t0, t1
        li    t3, 0x000f000f
        bne   t2, t3, fail
        or    t2, t0, t1
        li    t3, 0x0fff0fff
        bne   t2, t3, fail
        xor   t2, t0, t1
        li    t3, 0x0ff00ff0
        bne   t2, t3, fail
        andi  t2, t0, 0x0ff
        addi  t3, x0, 15
        bne   t2, t3, fail
        ori   t2, x0, 0x055
        addi  t3, x0, 0x55
        bne   t2, t3, fail
        xori  t2, t3, 0x0ff
        addi  t4, x0, 0x0aa
        bne   t2, t4, fail

        # Signed and unsigned comparisons must disagree for -1 versus 1.
        li    s11, 3
        addi  t0, x0, -1
        addi  t1, x0, 1
        slt   t2, t0, t1
        bne   t2, t1, fail
        sltu  t2, t0, t1
        bne   t2, x0, fail
        slti  t2, t0, 1
        bne   t2, t1, fail
        sltiu t2, t0, 1
        bne   t2, x0, fail

        # Shift amounts 0, 1, 31, and register value 32 (masked to five bits).
        li    s11, 4
        addi  t0, x0, 1
        addi  t1, x0, 0
        sll   t2, t0, t1
        bne   t2, t0, fail
        addi  t1, x0, 1
        sll   t2, t0, t1
        addi  t3, x0, 2
        bne   t2, t3, fail
        addi  t1, x0, 31
        sll   t2, t0, t1
        li    t3, 0x80000000
        bne   t2, t3, fail
        addi  t1, x0, 32
        sll   t2, t0, t1
        bne   t2, t0, fail
        slli  t2, t0, 31
        bne   t2, t3, fail
        srli  t2, t3, 31
        bne   t2, t0, fail
        srai  t2, t3, 31
        addi  t4, x0, -1
        bne   t2, t4, fail
        addi  t1, x0, 31
        srl   t2, t3, t1
        bne   t2, t0, fail
        sra   t2, t3, t1
        bne   t2, t4, fail

        # All six implemented branch conditions.
        li    s11, 5
        addi  t0, x0, -1
        addi  t1, x0, 1
        beq   t1, t1, beq_ok
        j     fail
beq_ok:
        bne   t0, t1, bne_ok
        j     fail
bne_ok:
        blt   t0, t1, blt_ok
        j     fail
blt_ok:
        bge   t1, t0, bge_ok
        j     fail
bge_ok:
        bltu  t0, t1, fail
        bgeu  t0, t1, bgeu_ok
        j     fail
bgeu_ok:

        # AUIPC and JAL link value; the sequential instruction must be flushed.
        li    s11, 6
        auipc t0, 0
        auipc t1, 0
        addi  t0, t0, 4
        bne   t0, t1, fail
        addi  s0, x0, 0
        auipc t0, 0
        jal   ra, jal_target
        addi  s0, x0, 1
jal_target:
        addi  t0, t0, 8
        bne   ra, t0, fail
        bne   s0, x0, fail

        # JALR target bit zero and link value; target is exactly 16 bytes ahead.
        li    s11, 7
        addi  s0, x0, 0
        auipc t0, 0
        addi  t0, t0, 17
        jalr  ra, 0(t0)
        addi  s0, x0, 1
jalr_target:
        addi  t1, t0, -5
        bne   ra, t1, fail
        bne   s0, x0, fail

pass:
        lui   t0, 0x40000
        lui   t1, 0x600d6
        addi  t1, t1, 13
        sw    t1, 12(t0)
done:
        j     done

fail:
        lui   t0, 0x40000
        lui   t1, 0xdead0
        add   t1, t1, s11
        sw    t1, 12(t0)
fail_loop:
        j     fail_loop

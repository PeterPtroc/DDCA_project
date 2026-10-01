# Directed pipeline dependency test. Architectural trace comparison detects any
# stale operand, duplicate retire, missing retire, or wrong-path commit.

        # EX/MEM forwarding into the next ALU instruction.
        li    s11, 1
        addi  s0, x0, 5
        addi  s1, x0, 7
        add   s2, s0, s1
        sub   s3, s2, s0
        addi  t0, x0, 7
        bne   s3, t0, fail

        # MEM/WB forwarding with one unrelated instruction in between.
        li    s11, 2
        add   s2, s0, s1
        addi  t6, x0, 0
        add   s3, s2, s0
        addi  t0, x0, 17
        bne   s3, t0, fail

        # Both operands forwarded from the same EX/MEM producer.
        li    s11, 3
        add   s2, s0, s1
        add   s3, s2, s2
        addi  t0, x0, 24
        bne   s3, t0, fail

        # Store-data forwarding followed by a load-use dependency.
        li    s11, 4
        lui   s4, 0x10000
        add   s2, s0, s1
        sw    s2, 0(s4)
        lw    s3, 0(s4)
        add   s5, s3, s0
        addi  t0, x0, 17
        bne   s5, t0, fail

        # Load-to-store must stall/forward the loaded store data correctly.
        li    s11, 5
        li    t0, 0x12345678
        sw    t0, 4(s4)
        lw    s2, 4(s4)
        sw    s2, 8(s4)
        lw    s3, 8(s4)
        bne   s3, t0, fail

        # A branch consumes the immediately preceding ALU result. Its wrong
        # path writes FAIL, so any flush bug terminates the trace as a failure.
        li    s11, 6
        lui   t4, 0x40000
        lui   t5, 0xdead0
        addi  t5, t5, 6
        addi  s0, x0, 3
        addi  s1, x0, 4
        addi  s3, x0, 7
        add   s2, s0, s1
        beq   s2, s3, branch_ok
        sw    t5, 12(t4)
branch_ok:

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

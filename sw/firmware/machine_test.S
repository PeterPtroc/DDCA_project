# RV32I/Zicsr/M-mode/precise-trap/CLINT directed regression.
_reset:
    li sp, 0x10010000
    li s0, 0x10000000
    la t0, trap_handler
    csrw mtvec, t0

    # Clear the handler mailbox.
    sw zero, 32(s0)
    sw zero, 36(s0)
    sw zero, 40(s0)
    sw zero, 44(s0)
    sw zero, 48(s0)
    sw zero, 52(s0)
    sw zero, 56(s0)

    # Load/store widths, sign extension, and byte enables.
    li t0, 0x80ff7f01
    sw t0, 0(s0)
    lb t1, 0(s0)
    li t2, 1
    bne t1, t2, fail
    lb t1, 1(s0)
    li t2, 127
    bne t1, t2, fail
    lb t1, 2(s0)
    li t2, -1
    bne t1, t2, fail
    lbu t1, 2(s0)
    li t2, 255
    bne t1, t2, fail
    lh t1, 0(s0)
    li t2, 0x7f01
    bne t1, t2, fail
    lh t1, 2(s0)
    li t2, 0xffff80ff
    bne t1, t2, fail
    lhu t1, 2(s0)
    li t2, 0x80ff
    bne t1, t2, fail
    li t0, 0xaa
    sb t0, 1(s0)
    li t0, 0x1234
    sh t0, 2(s0)
    lw t1, 0(s0)
    li t2, 0x1234aa01
    bne t1, t2, fail

    # Back-to-back CSR operations exercise CSR result forwarding.
    li t0, 0x12345678
    csrrw t1, mscratch, t0
    bne t1, zero, fail
    li t2, 0x0000f000
    csrrs t3, mscratch, t2
    bne t3, t0, fail
    li t4, 0x1234f678
    csrr t5, mscratch
    bne t5, t4, fail
    csrrwi t1, mscratch, 5
    bne t1, t4, fail
    csrrsi t2, mscratch, 2
    li t3, 5
    bne t2, t3, fail
    csrrci t2, mscratch, 1
    li t3, 7
    bne t2, t3, fail
    csrr t2, mscratch
    li t3, 6
    bne t2, t3, fail
    csrr t1, misa
    li t2, 0x40000100
    bne t1, t2, fail
    csrr t1, mhartid
    bne t1, zero, fail
    csrr t1, mcycle
    beq t1, zero, fail
    csrr t1, minstret
    beq t1, zero, fail
    fence
    fence.i

    # ECALL from M-mode.
    li t0, 11
    sw t0, 32(s0)
    sw zero, 40(s0)
    li t0, 4
    sw t0, 44(s0)
    ecall
    lw t0, 48(s0)
    li t1, 1
    bne t0, t1, fail

    # EBREAK.
    li t0, 3
    sw t0, 32(s0)
    ebreak
    lw t0, 48(s0)
    li t1, 2
    bne t0, t1, fail

    # Misaligned load and store traps include the bad address in mtval.
    li t0, 4
    sw t0, 32(s0)
    addi t1, s0, 1
    sw t1, 36(s0)
    li t0, 1
    sw t0, 40(s0)
    lw t2, 1(s0)
    lw t0, 48(s0)
    li t1, 3
    bne t0, t1, fail

    li t0, 6
    sw t0, 32(s0)
    addi t1, s0, 1
    sw t1, 36(s0)
    li t2, 0x55aa55aa
    sw t2, 4(s0)
    sw t2, 1(s0)
    lw t3, 4(s0)
    bne t2, t3, fail
    lw t0, 48(s0)
    li t1, 4
    bne t0, t1, fail

    # Instruction-address-misaligned trap.
    li t0, 0
    sw t0, 32(s0)
    la t4, misalign_target
    addi t4, t4, 2
    sw t4, 36(s0)
    jalr x0, 0(t4)
misalign_target:
    lw t0, 48(s0)
    li t1, 5
    bne t0, t1, fail

    # Illegal instruction: skip both the fault and a younger store. The store
    # must never become architecturally visible before the trap commits.
    li t0, 2
    sw t0, 32(s0)
    li t0, -1
    sw t0, 36(s0)
    li t0, 1
    sw t0, 40(s0)
    li t0, 8
    sw t0, 44(s0)
    sw zero, 80(s0)
    li t6, 0x11223344
    .word 0xffffffff
    sw t6, 80(s0)
    lw t0, 80(s0)
    bne t0, zero, fail
    lw t0, 48(s0)
    li t1, 6
    bne t0, t1, fail
    li t0, 4
    sw t0, 44(s0)

    # Machine timer interrupt through the standard CLINT addresses.
    li s2, 0x13579bdf
    li s3, 0x2468ace0
    li t0, 0x0200bff8
    lw t1, 0(t0)
    addi t1, t1, 200
    li t2, 0x02004000
    li t3, -1
    sw t3, 4(t2)
    sw t1, 0(t2)
    sw zero, 4(t2)
    li t0, 128
    csrs mie, t0
    li t0, 8
    csrs mstatus, t0
wait_timer:
    lw t0, 52(s0)
    beq t0, zero, wait_timer
    li t0, 0x13579bdf
    bne s2, t0, fail
    li t0, 0x2468ace0
    bne s3, t0, fail

    # Machine software interrupt.
    li t0, 8
    csrs mie, t0
    li t0, 0x02000000
    li t1, 1
    sw t1, 0(t0)
wait_software:
    lw t0, 56(s0)
    beq t0, zero, wait_software

    li t0, 0x40000000
    li t1, 0x600d600d
    sw t1, 12(t0)
pass_loop:
    j pass_loop

fail:
    li t0, 0x40000000
    li t1, 0xdeaddead
    sw t1, 12(t0)
fail_loop:
    j fail_loop

trap_handler:
    addi sp, sp, -40
    sw ra, 0(sp)
    sw t0, 4(sp)
    sw t1, 8(sp)
    sw t2, 12(sp)
    sw t3, 16(sp)
    sw t4, 20(sp)
    sw t5, 24(sp)
    sw t6, 28(sp)
    sw a0, 32(sp)

    csrr t0, mcause
    blt t0, zero, handle_interrupt
    li t1, 0x10000000
    lw t2, 32(t1)
    bne t0, t2, trap_fail
    lw t2, 40(t1)
    beq t2, zero, sync_tval_done
    csrr t3, mtval
    lw t2, 36(t1)
    bne t2, t3, trap_fail
sync_tval_done:
    lw t2, 48(t1)
    addi t2, t2, 1
    sw t2, 48(t1)
    csrr t2, mepc
    lw t3, 44(t1)
    add t2, t2, t3
    csrw mepc, t2
    j trap_return

handle_interrupt:
    li t1, 0x80000007
    beq t0, t1, timer_interrupt
    li t1, 0x80000003
    bne t0, t1, trap_fail
    li t1, 0x10000000
    li t2, 1
    sw t2, 56(t1)
    li t1, 0x02000000
    sw zero, 0(t1)
    li t1, 8
    csrc mie, t1
    j trap_return

timer_interrupt:
    li t1, 0x10000000
    li t2, 1
    sw t2, 52(t1)
    li t1, 0x02004000
    li t2, -1
    sw t2, 0(t1)
    sw t2, 4(t1)
    li t1, 128
    csrc mie, t1
    j trap_return

trap_fail:
    li t0, 0x40000000
    li t1, 0xdead0001
    sw t1, 12(t0)
    j fail_loop

trap_return:
    lw ra, 0(sp)
    lw t0, 4(sp)
    lw t1, 8(sp)
    lw t2, 12(sp)
    lw t3, 16(sp)
    lw t4, 20(sp)
    lw t5, 24(sp)
    lw t6, 28(sp)
    lw a0, 32(sp)
    addi sp, sp, 40
    mret

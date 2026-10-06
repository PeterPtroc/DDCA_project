    .section .text.ptrocos_app_call,"ax",@progbits
    .align 2
    .global ptrocos_app_call
    .global ptrocos_app_abort
// a0=entry, a1=API, a2=argc, a3=argv. The saved kernel frame survives faults
// in application registers. Switching SP is atomic with respect to interrupts.
ptrocos_app_call:
    csrci mstatus,8
    addi sp,sp,-64
    sw ra,0(sp)
    sw gp,4(sp)
    sw tp,8(sp)
    sw s0,12(sp)
    sw s1,16(sp)
    sw s2,20(sp)
    sw s3,24(sp)
    sw s4,28(sp)
    sw s5,32(sp)
    sw s6,36(sp)
    sw s7,40(sp)
    sw s8,44(sp)
    sw s9,48(sp)
    sw s10,52(sp)
    sw s11,56(sp)
    la t0,ptrocos_app_saved_sp
    sw sp,0(t0)
    mv t0,a0
    mv a0,a1
    mv a1,a2
    mv a2,a3
    li sp,0x80900000
    csrsi mstatus,8
    jalr ra,t0,0
    j .Lrestore
ptrocos_app_abort:
    li a0,-1
.Lrestore:
    csrci mstatus,8
    la t0,ptrocos_app_saved_sp
    lw sp,0(t0)
    lw ra,0(sp)
    lw gp,4(sp)
    lw tp,8(sp)
    lw s0,12(sp)
    lw s1,16(sp)
    lw s2,20(sp)
    lw s3,24(sp)
    lw s4,28(sp)
    lw s5,32(sp)
    lw s6,36(sp)
    lw s7,40(sp)
    lw s8,44(sp)
    lw s9,48(sp)
    lw s10,52(sp)
    lw s11,56(sp)
    addi sp,sp,64
    csrsi mstatus,8
    ret

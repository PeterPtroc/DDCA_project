    .section .text._app_start,"ax",@progbits
    .align 2
    .global _app_start
_app_start:
    j app_main
    .section .note.PtrocOS,"a",@note
    .align 2
    .long 8,16,1
    .asciz "PtrocOS"
    .long 1,4096,0x00010000,0x80800000

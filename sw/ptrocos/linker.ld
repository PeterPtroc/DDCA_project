OUTPUT_ARCH(riscv)
ENTRY(_reset)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
}

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.init))
        *(.text .text.*)
    } > ROM

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > ROM

    .data : ALIGN(4)
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM AT> ROM
    __data_load_start = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(16);
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    __freertos_irq_stack_top = __stack_top;
    __stack_limit = __stack_top - 4096;

    ASSERT(__bss_end <= __stack_limit, "RAM overflow: less than 4 KiB remains for startup/ISR stack")
    ASSERT((LOADADDR(.data) + SIZEOF(.data)) <= (ORIGIN(ROM) + LENGTH(ROM)), "ROM overflow")
}

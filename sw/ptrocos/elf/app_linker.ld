OUTPUT_ARCH(riscv)
ENTRY(_app_start)
MEMORY {
    CODE (rx) : ORIGIN = 0x00010000, LENGTH = 16K
    DATA (rw) : ORIGIN = 0x80800000, LENGTH = 1020K
}
PHDRS { code PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); abi PT_NOTE FLAGS(4); }
SECTIONS {
    .text : ALIGN(4) { KEEP(*(.text._app_start)) *(.text .text.*) } > CODE :code
    .rodata : ALIGN(4) { *(.rodata .rodata.* .srodata .srodata.*) } > CODE :code
    .note.PtrocOS : ALIGN(4) { KEEP(*(.note.PtrocOS)) } > CODE :code :abi
    .data : ALIGN(4) { LONG(0); *(.data .data.* .sdata .sdata.*) } > DATA :data
    .bss (NOLOAD) : ALIGN(4) { *(.bss .bss.* .sbss .sbss.*) *(COMMON) . = ALIGN(4); } > DATA :data
    /DISCARD/ : { *(.comment) *(.eh_frame*) *(.riscv.attributes) }
}

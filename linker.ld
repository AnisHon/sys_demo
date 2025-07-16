ENTRY(_start)

SECTIONS
{
    KERNEL_BASE = 0xC0000000;

    . = KERNEL_BASE;

    .text : AT(0x00000000) {
        *(.head)     /* head.s */
        *(.text*)    /* 所有C代码 */
    }

    .rodata : AT(ADDR(.text) + SIZEOF(.text)) {
        *(.rodata*)
    }

    .data : AT(ADDR(.rodata) + SIZEOF(.rodata)) {
        *(.data*)
    }

    .bss : AT(ADDR(.data) + SIZEOF(.data)) {
        *(.bss*)
        *(COMMON)
    }
}

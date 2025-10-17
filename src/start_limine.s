BITS 64
GLOBAL _start
EXTERN kmain

SECTION .text
align 16
_start:
    mov rdi, [rel boot_info_ptr]
    call kmain
.hang:
    hlt
    jmp .hang

SECTION .bss
boot_info_ptr: resq 1
stack_bottom:  resb 32768
stack_top:

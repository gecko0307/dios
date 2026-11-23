; stub.s - program entry point
bits 64

global _start
extern umain

section .text

; The kernel enters here in ring 3 with rdi = pointer to the argument string.
_start:
    and rsp, -16
    call umain    ; int umain(const(char)* args)
    mov rdi, rax
    xor eax, eax  ; SYS_EXIT
    syscall
.hang:
    jmp .hang

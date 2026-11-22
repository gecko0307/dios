; user/ulib.s - program entry point and the raw system call stub
bits 64

global _start
global sys_call
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

; long sys_call(ulong nr, ulong a0, ulong a1, ulong a2)
sys_call:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    syscall
    ret

; sys.s - DIOS system call stub
bits 64

global sys_call

section .text

; long sys_call(ulong nr, ulong a0, ulong a1, ulong a2)
sys_call:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    syscall
    ret

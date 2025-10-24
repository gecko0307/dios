BITS 64

global getCR3
global setCR3
global fastMemcpyNT

getCR3:
    mov rax, cr3
    ret

setCR3:
    ; CR3 writer for UEFI/x86_64 (SysV ABI):
    ; Caller provides physical PML4 in RDI. Mask low 12 bits and write CR3.
    mov rax, rdi
    and rax, 0xFFFFFFFFFFFFF000
    mov cr3, rax
    ret

fastMemcpyNT:
    mov rcx, rdx
    shr rcx, 3
    jz .tail

.loop:
    mov rax, [rsi]
    movnti [rdi], rax
    add rsi, 8
    add rdi, 8
    dec rcx
    jnz .loop

.tail:
    mov rcx, rdx
    and rcx, 7
    rep movsb
    
    sfence
    mov rax, rdi
    ret

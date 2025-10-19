global fastMemcpyNT

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

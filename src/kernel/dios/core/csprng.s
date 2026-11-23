; csprnd.s

bits 64
default rel

section .text

global rdrand64

; bool rdrand64(ulong* result)
; RDI = result
; EAX = return value

rdrand64:
    mov ecx, 10

.retry:
    rdrand rax
    jc .success

    loop .retry

    xor eax, eax
    ret

.success:
    mov [rdi], rax
    mov eax, 1
    ret

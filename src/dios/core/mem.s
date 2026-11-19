BITS 64

global getCR3
global setCR3
global fastMemcpyNT
global vmemInvalidatePage
global memcpy
global memmove
global memset
global memcmp
global enableSSE

section .text

getCR3:
    mov rax, cr3
    ret

; Caller provides the physical address of the PML4 in RDI (SysV ABI).
setCR3:
    mov rax, rdi
    and rax, 0xFFFFFFFFFFFFF000
    mov cr3, rax
    ret

; void vmemInvalidatePage(ulong vaddr)
vmemInvalidatePage:
    invlpg [rdi]
    ret

; void* fastMemcpyNT(void* dest, const void* src, size_t size)
; Returns dest (the old version returned the END pointer).
fastMemcpyNT:
    mov r8, rdi
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
    mov rax, r8
    ret

; The libc-style routines are written in asm on purpose: if they are written
; as plain byte loops in D, LLVM at -O2 recognises the loop and replaces it
; with a call to memcpy/memset - i.e. memcpy calls itself forever.
memcpy:
    mov rax, rdi
    mov rcx, rdx
    rep movsb
    ret

memset:
    mov r8, rdi
    mov eax, esi
    mov rcx, rdx
    rep stosb
    mov rax, r8
    ret

memmove:
    mov rax, rdi
    mov rcx, rdx
    cmp rdi, rsi
    jbe .fwd
    lea r8, [rsi + rdx]
    cmp rdi, r8
    jae .fwd
    ; overlapping with dest above src: copy backwards
    lea rsi, [rsi + rdx - 1]
    lea rdi, [rdi + rdx - 1]
    std
    rep movsb
    cld
    ret
.fwd:
    rep movsb
    ret

memcmp:
    mov rcx, rdx
    xor eax, eax
    test rcx, rcx
    jz .done
.next:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    sub eax, edx
    jnz .done
    inc rdi
    inc rsi
    dec rcx
    jnz .next
.done:
    ret

; Limine hands over with CR4.OSFXSR/OSXMMEXCPT cleared (CR4 = 0x20), so ANY
; SSE instruction raises #UD. The compiler emits SSE for things as innocent as
; zero-initialising a struct. Call this first thing in kmain.
enableSSE:
    mov rax, cr0
    btr rax, 2              ; CR0.EM = 0 (no x87 emulation)
    bts rax, 1              ; CR0.MP = 1
    mov cr0, rax
    mov rax, cr4
    or rax, 0x600           ; OSFXSR (bit 9) | OSXMMEXCPT (bit 10)
    mov cr4, rax
    fninit
    ret

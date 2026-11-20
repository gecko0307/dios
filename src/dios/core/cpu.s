; -------------------------
; src/dios/core/cpu.s
; CPU-level primitives: descriptor table loading, MSRs, cpuid, interrupt
; flag helpers and the interrupt entry stubs.
; -------------------------
bits 64

global gdtFlush
global idtLoad
global tssLoad
global cpuReadMsr
global cpuWriteMsr
global cpuCpuid
global cpuReadCr2
global cpuIrqSave
global cpuIrqRestore
global cpuSti
global cpuCli
global cpuHlt
global isrStubAddress

extern isrDispatch

section .text

; void gdtFlush(const void* gdtr)
; Loads the GDT, then reloads every segment register: CS through a far
; return, the data selectors directly. Layout (see gdt.d):
;   0x08 kernel code, 0x10 kernel data
gdtFlush:
    lgdt [rdi]
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    xor eax, eax            ; FS/GS: null selector (bases are set via MSRs later)
    mov fs, ax
    mov gs, ax
    pop rax                 ; return address
    push qword 0x08         ; new CS
    push rax                ; new RIP
    retfq

; void idtLoad(const void* idtr)
idtLoad:
    lidt [rdi]
    ret

; void tssLoad(ushort selector)
tssLoad:
    mov ax, di
    ltr ax
    ret

; ulong cpuReadMsr(uint msr)
cpuReadMsr:
    mov ecx, edi
    rdmsr
    shl rdx, 32
    or rax, rdx
    ret

; void cpuWriteMsr(uint msr, ulong value)
cpuWriteMsr:
    mov ecx, edi
    mov rax, rsi
    mov rdx, rsi
    shr rdx, 32
    wrmsr
    ret

; void cpuCpuid(uint leaf, uint subleaf, uint* out)   out = {eax, ebx, ecx, edx}
cpuCpuid:
    push rbx
    mov eax, edi
    mov ecx, esi
    mov r8, rdx
    cpuid
    mov [r8], eax
    mov [r8 + 4], ebx
    mov [r8 + 8], ecx
    mov [r8 + 12], edx
    pop rbx
    ret

; ulong cpuReadCr2()
cpuReadCr2:
    mov rax, cr2
    ret

; ulong cpuIrqSave()  - returns RFLAGS, interrupts are disabled afterwards
cpuIrqSave:
    pushfq
    pop rax
    cli
    ret

; void cpuIrqRestore(ulong flags)  - re-enables interrupts only if they were on
cpuIrqRestore:
    test edi, 0x200
    jz .done
    sti
.done:
    ret

cpuSti:
    sti
    ret

cpuCli:
    cli
    ret

; Enable interrupts and halt in one go: STI holds interrupts off for one
; more instruction, so an IRQ cannot slip in between and be missed until the
; next one.
cpuHlt:
    sti
    hlt
    ret

; void* isrStubAddress(uint vector)
isrStubAddress:
    mov edi, edi
    lea rax, [rel isr_stub_table]
    mov rax, [rax + rdi * 8]
    ret

; ---------------------------------------------------------------------------
; Interrupt stubs. One per vector; each normalises the stack to
;   [vector][error code][RIP][CS][RFLAGS][RSP][SS]
; (pushing a dummy error code where the CPU does not) and joins isr_common.
; Vectors with a hardware error code: 8, 10, 11, 12, 13, 14, 17, 21, 29, 30.
; ---------------------------------------------------------------------------
%assign i 0
%rep 256
isr_stub_ %+ i:
%if (i == 8) || (i == 10) || (i == 11) || (i == 12) || (i == 13) || (i == 14) || (i == 17) || (i == 21) || (i == 29) || (i == 30)
%else
    push qword 0
%endif
    push qword i
    jmp isr_common
%assign i i+1
%endrep

; Frame seen by D (see InterruptFrame in idt.d): r15 is at the lowest address.
isr_common:
    push rax
    push rcx
    push rdx
    push rbx
    push rbp
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    cld                     ; the interrupted code may have been in the middle of a backwards memmove
    mov rbx, rsp            ; callee-saved: survives the call
    sub rsp, 512            ; FXSAVE area: compiled D code freely uses SSE,
    and rsp, -16            ; so the interrupted code's XMM state must be preserved
    fxsave [rsp]

    mov rdi, rbx            ; InterruptFrame*
    call isrDispatch

    fxrstor [rsp]
    mov rsp, rbx

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rbp
    pop rbx
    pop rdx
    pop rcx
    pop rax
    add rsp, 16             ; vector + error code
    iretq

section .rodata
align 8
isr_stub_table:
%assign i 0
%rep 256
    dq isr_stub_ %+ i
%assign i i+1
%endrep

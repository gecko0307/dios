; -------------------------
; dios/core/cpu.s
; CPU-level primitives: descriptor table loading, MSRs, cpuid, interrupt
; flag helpers and the interrupt entry stubs.
; -------------------------
bits 64

global sseEnable
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
global cpuTripleFault
global syscallEntryAddress
global syscallSetStack
global userEnter
global userResume
global isrStubAddress

extern isrDispatch
extern syscallDispatch

section .text

; void sseEnable()
sseEnable:
    mov rax, cr0
    btr rax, 2              ; CR0.EM = 0 (no x87 emulation)
    bts rax, 1              ; CR0.MP = 1
    mov cr0, rax
    mov rax, cr4
    or rax, 0x600           ; OSFXSR (bit 9) | OSXMMEXCPT (bit 10)
    mov cr4, rax
    fninit
    ret

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

; void cpuTripleFault() - last-resort reset: load an empty IDT, then raise an
; exception. With no handler the #UD escalates to #DF and then a triple fault,
; which makes the chipset reset the machine. Never returns.
cpuTripleFault:
    cli
    sub rsp, 16
    mov word [rsp], 0
    mov qword [rsp + 2], 0
    lidt [rsp]
    ud2
.hang:
    hlt
    jmp .hang

; ---------------------------------------------------------------------------
; Ring 3 support
;
; SYSCALL convention (user side): rax = number, rdi/rsi/rdx = arguments, result
; in rax; rcx and r11 are clobbered (hardware). SFMASK clears IF/TF/DF, so the
; handler starts with interrupts off on the shared ring-0 stack.
; ---------------------------------------------------------------------------

; void* syscallEntryAddress()
syscallEntryAddress:
    lea rax, [rel syscallEntry]
    ret

; void syscallSetStack(ulong top)
syscallSetStack:
    mov [rel sys_kstack_top], rdi
    ret

syscallEntry:
    mov [rel sys_user_rsp], rsp
    mov rsp, [rel sys_kstack_top]
    push qword [rel sys_user_rsp]   ; user RSP
    push rcx                        ; user RIP
    push r11                        ; user RFLAGS
    sub rsp, 8                      ; keep the call site 16-byte aligned
    ; syscallDispatch(nr, a0, a1, a2)
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rax
    cld
    call syscallDispatch
    add rsp, 8
    pop r11
    pop rcx
    pop rsp                         ; back on the user stack
    o64 sysret

; long userEnter(ulong entry, ulong userStackTop, ulong arg0)
; Saves the kernel context, then drops to ring 3 with an iretq frame. Returns
; (as if from this call) when userResume() is invoked, with its argument in rax.
userEnter:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov [rel user_resume_rsp], rsp
    mov rax, rdx
    push qword 0x1B                 ; SS  = user data | 3
    push rsi                        ; RSP
    push qword 0x202                ; RFLAGS: IF
    push qword 0x23                 ; CS  = user code | 3
    push rdi                        ; RIP
    mov rdi, rax                    ; arg0 reaches the program in rdi
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    xor esi, esi
    xor ebp, ebp
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
    iretq

; void userResume(long code)   - never returns to its caller
; Abandons whatever stack we are on (syscall, exception or IRQ) and returns
; from userEnter() to the kernel code that started the program.
userResume:
    mov rsp, [rel user_resume_rsp]
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov rax, rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
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

section .bss
align 8
sys_kstack_top:   resq 1
sys_user_rsp:     resq 1
user_resume_rsp:  resq 1

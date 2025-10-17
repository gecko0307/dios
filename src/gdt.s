[BITS 32]
global load_gdt

; void load_gdt(Gdtr* gdtr);
load_gdt:
    mov eax, [esp+4] 
    lgdt [eax]

    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    jmp 0x08:flush_cs

flush_cs:
    ret

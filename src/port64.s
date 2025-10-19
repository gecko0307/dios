; -------------------------
; src/port64.s
; -------------------------
bits 64

global kPortReadByte
global kPortWriteByte
global kPortWrite16
global kPortRead32
global kPortWrite32

kPortReadByte:
    mov dx, di
    in  al, dx
    movzx eax, al
    ret

kPortWriteByte:
    mov dx, di
    mov al, sil
    out dx, al
    ret

kPortWrite16:
    mov dx, di
    mov ax, si
    out dx, ax
    ret

kPortRead32:
    mov dx, di
    in  eax, dx
    ret

kPortWrite32:
    mov dx, di
    mov eax, esi
    out dx, eax
    ret

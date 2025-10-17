; -------------------------
; src/port64.s
; -------------------------
bits 64

global kPortReadByte
global kPortWriteByte

global kPortReadByte
global kPortWriteByte

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

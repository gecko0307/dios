; -------------------------
; src/port.s
; -------------------------
bits 32

global kPortReadByte
global kPortWriteByte

kPortReadByte:
    push ebp
    mov ebp, esp
    mov dx, [ebp+8]
    in al, dx
    movzx eax, al
    pop ebp
    ret

kPortWriteByte:
    push ebp
    mov ebp, esp
    mov dx, [ebp+8]
    mov al, [ebp+12]
    out dx, al
    pop ebp
    ret

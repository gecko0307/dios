global start
extern kmain
extern start_ctors, end_ctors, start_dtors, end_dtors

MULTIBOOT_PAGE_ALIGN  equ 0x00000001
MULTIBOOT_MEMORY_INFO equ 0x00000002
MULTIBOOT_VIDEO_MODE  equ 0x00000004
MULTIBOOT_AOUT_KLUDGE equ 0x00010000

FLAGS    equ MULTIBOOT_PAGE_ALIGN | MULTIBOOT_MEMORY_INFO | MULTIBOOT_VIDEO_MODE
MAGIC    equ 0x1BADB002
CHECKSUM equ -(MAGIC + FLAGS)

section .text      ; Next is the Grub Multiboot Header

section .multiboot
align 4

MultiBootHeader:
    dd MAGIC
    dd FLAGS
    dd CHECKSUM
    dd 0               ; header_addr
    dd 0               ; load_addr
    dd 0               ; load_end_addr;
    dd 0               ; bss_end_addr;
    dd 0               ; entry_addr;
    dd 0               ; mode_type (0=graphics, 1=text)
    dd 640             ; width
    dd 480             ; height
    dd 32              ; depth

; reserve initial kernel stack space
STACKSIZE equ 0x4000  ; 16k

static_ctors_loop:
    mov ebx, start_ctors
    jmp .test
.body:
    call [ebx]
    add ebx, 4
.test:
    cmp ebx, end_ctors
    jb .body

start:
    mov  esp, STACKSIZE+stack
    push ebx ; Multiboot info structure
    push eax ; Multiboot magic number
    call kmain

static_dtors_loop:
    mov ebx, start_dtors
    jmp .test
.body:
    call [ebx]
    add ebx, 4
.test:
    cmp ebx, end_dtors
    jb .body

cpuhalt:
    hlt
    jmp cpuhalt

section .bss
align 32

stack:
    resb STACKSIZE

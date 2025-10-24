ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/main.d -of=o-elf-x86/main.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/bootloader/multiboot.d -of=o-elf-x86/dios/bootloader/multiboot.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/gdt.d -of=o-elf-x86/dios/core/gdt.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/vga.d -of=o-elf-x86/dios/core/vga.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/keyboard.d -of=o-elf-x86/dios/core/keyboard.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/mem.d -of=o-elf-x86/dios/core/mem.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/ps2.d -of=o-elf-x86/dios/core/ps2.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/framebuffer.d -of=o-elf-x86/dios/core/framebuffer.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/paging.d -of=o-elf-x86/dios/core/paging.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/pit.d -of=o-elf-x86/dios/core/pit.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/logo.d -of=o-elf-x86/dios/core/logo.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/cursor.d -of=o-elf-x86/dios/core/cursor.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/font.d -of=o-elf-x86/dios/core/font.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/console.d -of=o-elf-x86/dios/core/console.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/stdio.d -of=o-elf-x86/dios/core/stdio.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/dios/core/error.d -of=o-elf-x86/dios/core/error.o
nasm -f elf -o o-elf-x86/start.s.o src/start.s
nasm -f elf -o o-elf-x86/dios/core/port.s.o src/dios/core/port.s
nasm -f elf -o o-elf-x86/dios/core/gdt.s.o src/dios/core/gdt.s
ld.lld -m elf_i386 -T linker.ld -o cdroot/kernel.bin o-elf-x86/start.s.o o-elf-x86/main.o o-elf-x86/dios/core/gdt.o o-elf-x86/bootloader/multiboot.o o-elf-x86/dios/core/port.s.o o-elf-x86/dios/core/gdt.s.o o-elf-x86/dios/core/vga.o o-elf-x86/dios/core/framebuffer.o o-elf-x86/dios/core/paging.o o-elf-x86/dios/core/pit.o o-elf-x86/dios/core/mem.o o-elf-x86/dios/core/ps2.o o-elf-x86/dios/core/keyboard.o o-elf-x86/dios/core/logo.o o-elf-x86/dios/core/cursor.o o-elf-x86/dios/core/font.o o-elf-x86/dios/core/console.o o-elf-x86/dios/core/stdio.o o-elf-x86/dios/core/error.o
mkisofs -R -J -b boot/grub2/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table -o dios.iso ./cdroot

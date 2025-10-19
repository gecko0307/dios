ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/main.d -of=o-elf-x86/main.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/bootloader/multiboot.d -of=o-elf-x86/bootloader/multiboot.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/gdt.d -of=o-elf-x86/core/gdt.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/vga.d -of=o-elf-x86/core/vga.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/keyboard.d -of=o-elf-x86/core/keyboard.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/mem.d -of=o-elf-x86/core/mem.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/ps2.d -of=o-elf-x86/core/ps2.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/framebuffer.d -of=o-elf-x86/core/framebuffer.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/paging.d -of=o-elf-x86/core/paging.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/pit.d -of=o-elf-x86/core/pit.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/logo.d -of=o-elf-x86/logo.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/cursor.d -of=o-elf-x86/cursor.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/font.d -of=o-elf-x86/font.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/console.d -of=o-elf-x86/console.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/stdio.d -of=o-elf-x86/stdio.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/error.d -of=o-elf-x86/error.o
nasm -f elf -o o-elf-x86/start.s.o src/start.s
nasm -f elf -o o-elf-x86/port.s.o src/port.s
nasm -f elf -o o-elf-x86/gdt.s.o src/gdt.s
ld.lld -m elf_i386 -T linker.ld -o cdroot/kernel.bin o-elf-x86/start.s.o o-elf-x86/main.o o-elf-x86/core/gdt.o o-elf-x86/bootloader/multiboot.o o-elf-x86/port.s.o o-elf-x86/gdt.s.o o-elf-x86/core/vga.o o-elf-x86/core/framebuffer.o o-elf-x86/core/paging.o o-elf-x86/core/pit.o o-elf-x86/core/mem.o o-elf-x86/core/ps2.o o-elf-x86/core/keyboard.o o-elf-x86/logo.o o-elf-x86/cursor.o o-elf-x86/font.o o-elf-x86/console.o o-elf-x86/stdio.o o-elf-x86/error.o
mkisofs -R -J -b boot/grub2/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table -o dios.iso ./cdroot

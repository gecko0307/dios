ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/main.d -of=o-elf-x86/main.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/bootloader/multiboot.d -of=o-elf-x86/bootloader/multiboot.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/gdt.d -of=o-elf-x86/core/gdt.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/console.d -of=o-elf-x86/core/console.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/error.d -of=o-elf-x86/core/error.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/stdarg.d -of=o-elf-x86/core/stdarg.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/stddef.d -of=o-elf-x86/core/stddef.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/stdio.d -of=o-elf-x86/core/stdio.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/string.d -of=o-elf-x86/core/string.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/vga.d -of=o-elf-x86/core/vga.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/keyboard.d -of=o-elf-x86/core/keyboard.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/ps2.d -of=o-elf-x86_64/core/ps2.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/framebuffer.d -of=o-elf-x86_64/core/framebuffer.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/core/pit.d -of=o-elf-x86_64/core/pit.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/logo.d -of=o-elf-x86/logo.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/cursor.d -of=o-elf-x86/cursor.o
ldc2 -c -betterC -I=src -mtriple=i386-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 src/font.d -of=o-elf-x86/font.o
nasm -f elf -o o-elf-x86/start.s.o src/start.s
nasm -f elf -o o-elf-x86/port.s.o src/port.s
nasm -f elf -o o-elf-x86/gdt.s.o src/gdt.s
ld.lld -m elf_i386 -T linker.ld -o cdroot/kernel.bin o-elf-x86/start.s.o o-elf-x86/main.o o-elf-x86/core/gdt.o o-elf-x86/core/console.o o-elf-x86/core/error.o o-elf-x86/bootloader/multiboot.o o-elf-x86/port.s.o o-elf-x86/gdt.s.o o-elf-x86/core/stdarg.o o-elf-x86/core/stddef.o o-elf-x86/core/stdio.o o-elf-x86/core/string.o o-elf-x86/core/vga.o o-elf-x86_64/core/framebuffer.o o-elf-x86_64/core/pit.o o-elf-x86_64/core/ps2.o o-elf-x86/core/keyboard.o o-elf-x86/logo.o o-elf-x86/cursor.o o-elf-x86/font.o
mkisofs -R -J -b boot/grub2/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table -o dios.iso ./cdroot

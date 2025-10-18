ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/main64.d -of=o-elf-x86_64/main64.o
ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/bootloader/limine.d -of=o-elf-x86_64/bootloader/limine.o
ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/core/mem.d -of=o-elf-x86_64/core/mem.o
ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/core/ps2.d -of=o-elf-x86_64/core/ps2.o
ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/core/pit.d -of=o-elf-x86_64/core/pit.o
ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/core/framebuffer.d -of=o-elf-x86_64/core/framebuffer.o
ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/logo.d -of=o-elf-x86_64/logo.o
ldc2 -c -betterC -I=src -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone src/cursor.d -of=o-elf-x86_64/cursor.o
nasm -f elf64 -o o-elf-x86_64/port64.s.o src/port64.s
ld.lld -m elf_x86_64 -T linker64.ld -z max-page-size=0x1000 -static --gc-sections -nostdlib -o cdroot64/kernel64.bin o-elf-x86_64/main64.o o-elf-x86_64/bootloader/limine.o o-elf-x86_64/port64.s.o o-elf-x86_64/core/mem.o o-elf-x86_64/core/ps2.o o-elf-x86_64/core/pit.o o-elf-x86_64/core/framebuffer.o o-elf-x86_64/logo.o o-elf-x86_64/cursor.o
xorriso -as mkisofs -r -b limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e limine/limine-uefi-cd.bin -no-emul-boot --efi-boot-part --efi-boot-image --protective-msdos-label -o dios64.iso ./cdroot64

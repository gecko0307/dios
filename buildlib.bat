mkdir o-elf-x86_64\lib\dios
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=lib lib/object.d -of=o-elf-x86_64/lib/object.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=lib lib/dios/ulib.d -of=o-elf-x86_64/lib/dios/ulib.o
nasm -f elf64 -o o-elf-x86_64/lib/dios/ulib.s.o lib/dios/ulib.s
llvm-ar rcs libulib.a o-elf-x86_64/lib/object.o o-elf-x86_64/lib/dios/ulib.o o-elf-x86_64/lib/dios/ulib.s.o

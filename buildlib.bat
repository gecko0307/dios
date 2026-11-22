mkdir o-elf-x86_64\ulib\dios
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/object.d -of=o-elf-x86_64/ulib/object.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/umain.d -of=o-elf-x86_64/ulib/umain.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/dios/ulib.d -of=o-elf-x86_64/ulib/dios/ulib.o
nasm -f elf64 -o o-elf-x86_64/ulib/dios/ulib.s.o src/ulib/dios/ulib.s
llvm-ar rcs libulib.a o-elf-x86_64/ulib/object.o o-elf-x86_64/ulib/umain.o o-elf-x86_64/ulib/dios/ulib.o o-elf-x86_64/ulib/dios/ulib.s.o

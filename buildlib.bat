mkdir o-elf-x86_64\ulib\ulib\core
mkdir o-elf-x86_64\ulib\ulib\dios
mkdir o-elf-x86_64\ulib\ulib\math
mkdir o-elf-x86_64\ulib\ulib\gfx
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/object.d -of=o-elf-x86_64/ulib/object.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/umain.d -of=o-elf-x86_64/ulib/umain.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/dios/sys.d -of=o-elf-x86_64/ulib/ulib/dios/sys.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/dios/alloc.d -of=o-elf-x86_64/ulib/ulib/dios/alloc.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/dios/mem.d -of=o-elf-x86_64/ulib/ulib/dios/mem.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/dios/io.d -of=o-elf-x86_64/ulib/ulib/dios/io.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/math/base.d -of=o-elf-x86_64/ulib/ulib/math/base.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/gfx/proto.d -of=o-elf-x86_64/ulib/ulib/gfx/proto.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/gfx/canvas.d -of=o-elf-x86_64/ulib/ulib/gfx/canvas.o
ldc2 -c -mtriple=x86_64-none-elf -release -nodefaultlib --boundscheck=off --disable-red-zone --use-ctors=0 --fno-exceptions --nogc -O0 -I=src/ulib src/ulib/ulib/gfx/window.d -of=o-elf-x86_64/ulib/ulib/gfx/window.o
nasm -f elf64 -o o-elf-x86_64/ulib/ulib/dios/sys.s.o src/ulib/ulib/dios/sys.s
nasm -f elf64 -o o-elf-x86_64/ulib/stub.s.o src/ulib/stub.s
llvm-ar rcs rootfs/lib/libulib.a o-elf-x86_64/ulib/object.o o-elf-x86_64/ulib/umain.o o-elf-x86_64/ulib/ulib/dios/sys.o o-elf-x86_64/ulib/ulib/dios/sys.s.o o-elf-x86_64/ulib/ulib/dios/alloc.o o-elf-x86_64/ulib/ulib/dios/mem.o o-elf-x86_64/ulib/ulib/dios/io.o o-elf-x86_64/ulib/ulib/math/base.o o-elf-x86_64/ulib/ulib/gfx/proto.o o-elf-x86_64/ulib/ulib/gfx/canvas.o o-elf-x86_64/ulib/ulib/gfx/window.o o-elf-x86_64/ulib/stub.s.o

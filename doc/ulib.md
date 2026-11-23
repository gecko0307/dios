# ulib Runtime Library

ulib is a low-level runtime library for DIOS applications written in D. Most of its functions are libc-like and self-explanatory.

## ulib.dios.sys

DIOS kernel functions.

`void uexit(long code)`

`void uwrite(const(char)* s, size_t n)`

`int ugetkey(bool block)`

`void usleep(ulong ms)`

`ulong uticks()`

`void uyield()`

`int ugetpid()`

`void uclear()`

`int uopen(const(char)* path)`

`long uread(int fd, void* buf, size_t n)`

`int uclose(int fd)`

`long useek(int fd, long offset, int whence)`

`int ustat(const(char)* path, UStat* st)`

`int ureaddir(int fd, UDirent* e)`

`long ugetcwd(char* buf, size_t n)`

`void* ubrk(void* newBreak)`

## ulib.dios.alloc

Heap allocator like C's `malloc`/`free`.

`void* umalloc(size_t size)`

`void* ucalloc(size_t count, size_t size)`

`void* urealloc(void* ptr, size_t size)`

`void ufree(void* ptr)`

`bool uheapGetStats(UHeapStats* stats)`

## ulib.dios.mem

Memory helpers.

`void* memset(void* dst, int c, size_t n)`

`void* memcpy(void* dst, const(void)* src, size_t n)`

`void* memmove(void* dst, const(void)* src, size_t n)`

`int memcmp(const(void)* vl, const(void)* vr, size_t n)`

`size_t ustrlen(const(char)* s)`

## ulib.dios.io

Basic input/output functions.

`void uputs(const(char)* s)`

`void uputc(char c)`

`void uputu(ulong v)`

`void uputi(long v)`

`void uputhex(ulong v)`

`void uputf(double v, uint precision = 6)`

## ulib.math

Elementary math functions.

`bool isNaN(T)(T x)`

`int isInfinity(T)(T x)`

`bool signbit(T)(T x)`

`T copysign(T, R)(T mag, R sgn)`

`T abs(T)(T v)`

`T fabs(T)(T x)`

`T fmax(T)(T x, T y)`

`T fmin(T)(T x, T y)`

`T rint(T)(T x)`

`T sqrt(T)(T x)`

`T cbrt(T)(T x)`

`T sin(T)(T x)`

`T cos(T)(T x)`

`T tan(T)(T x)`

`T asin(T)(T x)`

`T acos(T)(T x)`

`T atan(T)(T x)`

`T atan2(T)(T y, T x)`

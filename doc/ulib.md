# ulib Runtime Library

ulib is a low-level runtime library for DIOS applications written in D. Most of its functions are libc-like and self-explanatory.

Many functions are prefixed with "u" to avoid conflicts with libc (should libc be introduced in the future), because they are not 100% compatible.

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

`void* ubrk(void* newBreak)`

`void udatetime(DateTime* dt)`

`void urandom(void* buffer, size_t size)`

`int uspawn(const(char)* path, const(char)* args, uint stdoutTarget)`

`bool utaskalive(int id)`

`int utaskfind(const(char)* name)`

`long usysstr(char* buf, size_t size, uint strid)`

`int uopen(const(char)* path, int flags)`

`long uread(int fd, void* buf, size_t n)`

`long ureadfull(int fd, void* buf, size_t len)`

`long ufwrite(int fd, const(void)* buf, size_t n)`

`int uclose(int fd)`

`long useek(int fd, long offset, int whence)`

`int ustat(const(char)* path, UStat* st)`

`int ureaddir(int fd, UDirent* e)`

`long ugetcwd(char* buf, size_t n)`

`int uunlink(const(char)* path)`

`int umkdir(const(char)* path)`

`int urmdir(const(char)* path)`

`int urename(const(char)* from, const(char)* to)`

`int uchdir(const(char)* path)`

`long urealpath(const(char)* path, char* buf, size_t n)`

`void utargetpath(const(char)* src, const(char)* dst, char* out_, size_t cap)`

`void usync()`

`const(char)* uerrstr(int err)`

`void uperror(const(char)* what, const(char)* path, int err)`

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

`size_t alignUp(size_t value, size_t alignment)`

`size_t alignDown(size_t a, size_t alignment)`

## ulib.dios.io

Basic input/output functions.

`void uputs(const(char)* s)`

`void uputs_b(const(char)* s)`

`void uputc(char c)`

`void uputc_b(char c)`

`void uputu(ulong v)`

`void uputu_b(ulong v)`

`void uputi(long v)`

`void uputi_b(long v)`

`void uputhex(ulong v)`

`void uputhex_b(ulong v)`

`void uputf(double v, uint precision = 6)`

`void uputf_b(double v, uint precision = 6)`

`void uflush_b()`

`int uprintf(const(char)* fmt, ...)`

`uput*` functions are available in two forms: buffered (`_b`) and immediate. Buffered functions don't print immediately, their output is stored in a ring buffer and sent to the kernel by calling `uflush_b`. This makes the output atomic. `uprintf` uses this mechanism to print whole lines that are not messed up at scheduler interrupts.

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

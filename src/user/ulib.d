/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/
module ulib;

// Everything a DIOS user program needs: system call wrappers, a few printing
// helpers and the memory functions the compiler may call.

enum ulong SYS_EXIT = 0;
enum ulong SYS_WRITE = 1;
enum ulong SYS_GETKEY = 2;
enum ulong SYS_SLEEP = 3;
enum ulong SYS_TICKS = 4;
enum ulong SYS_CLEAR = 5;
enum ulong SYS_OPEN = 6;
enum ulong SYS_READ = 7;
enum ulong SYS_CLOSE = 8;
enum ulong SYS_SEEK = 9;
enum ulong SYS_STAT = 10;
enum ulong SYS_READDIR = 11;
enum ulong SYS_GETCWD = 12;

// useek() origins
enum int SEEK_SET = 0;
enum int SEEK_CUR = 1;
enum int SEEK_END = 2;

// Layouts shared with the kernel (sysfile.d)
struct UStat
{
    ulong size;
    uint mtime;                 // DOS timestamp: (year-1980)<<25 | month<<21 | day<<16 | hour<<11 | min<<5 | sec/2
    uint isDir;
}

struct UDirent
{
    ulong size;
    uint mtime;
    uint isDir;
    char[256] name;
}

// Key codes returned by getkey (besides plain ASCII; Enter is 10).
enum int KEY_UP = 0x101;
enum int KEY_DOWN = 0x102;
enum int KEY_LEFT = 0x103;
enum int KEY_RIGHT = 0x104;
enum int KEY_HOME = 0x105;
enum int KEY_END = 0x106;
enum int KEY_DELETE = 0x107;

extern(C):

long sys_call(ulong nr, ulong a0, ulong a1, ulong a2) @nogc nothrow;

void* memset(void* dst, int c, size_t n) @nogc nothrow
{
    ubyte* p = cast(ubyte*)dst;
    for (size_t i = 0; i < n; i++)
        p[i] = cast(ubyte)c;
    return dst;
}

void* memcpy(void* dst, const(void)* src, size_t n) @nogc nothrow
{
    ubyte* d = cast(ubyte*)dst;
    const(ubyte)* s = cast(const(ubyte)*)src;
    for (size_t i = 0; i < n; i++)
        d[i] = s[i];
    return dst;
}

void* memmove(void* dst, const(void)* src, size_t n) @nogc nothrow
{
    ubyte* d = cast(ubyte*)dst;
    const(ubyte)* s = cast(const(ubyte)*)src;
    if (d < s)
    {
        for (size_t i = 0; i < n; i++)
            d[i] = s[i];
    }
    else
    {
        for (size_t i = n; i > 0; i--)
            d[i - 1] = s[i - 1];
    }
    return dst;
}

void uexit(long code) @nogc nothrow
{
    sys_call(SYS_EXIT, cast(ulong)code, 0, 0);
}

size_t ustrlen(const(char)* s) @nogc nothrow
{
    size_t n = 0;
    while (s[n] != 0)
        n++;
    return n;
}

void uwrite(const(char)* s, size_t n) @nogc nothrow
{
    sys_call(SYS_WRITE, cast(ulong)s, n, 0);
}

void uputs(const(char)* s) @nogc nothrow
{
    uwrite(s, ustrlen(s));
}

void uputc(char c) @nogc nothrow
{
    uwrite(&c, 1);
}

void uputu(ulong v) @nogc nothrow
{
    char[20] d;
    uint k = 20;
    do
    {
        d[--k] = cast(char)('0' + v % 10);
        v /= 10;
    }
    while (v != 0);
    uwrite(d.ptr + k, 20 - k);
}

void uputhex(ulong v) @nogc nothrow
{
    char[16] d;
    for (int i = 15; i >= 0; i--)
    {
        uint nib = cast(uint)(v & 15);
        d[i] = cast(char)(nib < 10 ? '0' + nib : 'a' + nib - 10);
        v >>= 4;
    }
    uwrite("0x".ptr, 2);
    uwrite(d.ptr, 16);
}

/// Next key (ASCII, Enter = 10, or KEY_*). With block == false returns -1 if none is waiting.
int ugetkey(bool block) @nogc nothrow
{
    return cast(int)sys_call(SYS_GETKEY, block ? 1 : 0, 0, 0);
}

void usleep(ulong ms) @nogc nothrow
{
    sys_call(SYS_SLEEP, ms, 0, 0);
}

ulong uticks() @nogc nothrow
{
    return cast(ulong)sys_call(SYS_TICKS, 0, 0, 0);
}

void uclear() @nogc nothrow
{
    sys_call(SYS_CLEAR, 0, 0, 0);
}

// Files (read-only). Paths are relative to the shell's current directory or absolute.
// At most 8 files can be open at once; they are closed when the program ends.

/// File descriptor of a file or directory, or -1.
int uopen(const(char)* path) @nogc nothrow
{
    return cast(int)sys_call(SYS_OPEN, cast(ulong)path, 0, 0);
}

/// Bytes read (0 = end of file), or -1.
long uread(int fd, void* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_READ, cast(ulong)fd, cast(ulong)buf, n);
}

int uclose(int fd) @nogc nothrow
{
    return cast(int)sys_call(SYS_CLOSE, cast(ulong)fd, 0, 0);
}

/// New position, or -1.
long useek(int fd, long offset, int whence) @nogc nothrow
{
    return sys_call(SYS_SEEK, cast(ulong)fd, cast(ulong)offset, cast(ulong)whence);
}

/// 0 on success, -1 if the path does not exist.
int ustat(const(char)* path, UStat* st) @nogc nothrow
{
    return cast(int)sys_call(SYS_STAT, cast(ulong)path, cast(ulong)st, 0);
}

/// Next entry of a directory opened with uopen(): 1 = filled in, 0 = no more, -1 = error.
int ureaddir(int fd, UDirent* e) @nogc nothrow
{
    return cast(int)sys_call(SYS_READDIR, cast(ulong)fd, cast(ulong)e, 0);
}

/// Current directory into buf; returns its length or -1.
long ugetcwd(char* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_GETCWD, cast(ulong)buf, n, 0);
}

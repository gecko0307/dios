module ulib;

// Everything a DIOS user program needs: system call wrappers, a few printing
// helpers and the memory functions the compiler may call.

enum ulong SYS_EXIT = 0;
enum ulong SYS_WRITE = 1;
enum ulong SYS_GETKEY = 2;
enum ulong SYS_SLEEP = 3;
enum ulong SYS_TICKS = 4;
enum ulong SYS_CLEAR = 5;

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

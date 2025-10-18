module core.mem;

extern(C):

void* memcpy(void* dest, const void* src, size_t n) @nogc nothrow
{
    auto d = cast(ubyte*)dest;
    auto s = cast(const ubyte*)src;
    for (size_t i = 0; i < n; i++)
    {
        d[i] = s[i];
    }
    return dest;
}

void* memset(void *s, int c, size_t n) @nogc nothrow
{
    ubyte* p = cast(ubyte*)s;

    for (size_t i = 0; i < n; i++)
    {
        p[i] = cast(ubyte)c;
    }

    return s;
}

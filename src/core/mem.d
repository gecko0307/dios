module core.mem;

struct RAMInfo
{
    size_t availMemBase;
    size_t availMemSize;
    size_t hhdmOffset;
    size_t kernelBasePhysical;
    size_t kernelBaseVirtual;
    size_t kernelSize;
}

extern(C):

size_t alignDown(size_t a, size_t alignment) @nogc nothrow
{
    return a & ~(alignment - 1);
}

size_t alignUp(size_t value, size_t alignment) @nogc nothrow
{
    return (value + alignment - 1) & ~(alignment - 1);
}

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

version(X86_64)
{
    // from mem.s
    void* fastMemcpyNT(void* dest, const void* src, size_t size)  @nogc nothrow;
}

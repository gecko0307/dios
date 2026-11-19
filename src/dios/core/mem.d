module dios.core.mem;

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

version(X86_64)
{
    // All implemented in mem.s (see the comment there for why).
    void* memcpy(void* dest, const(void)* src, size_t n) @nogc nothrow;
    void* memmove(void* dest, const(void)* src, size_t n) @nogc nothrow;
    void* memset(void* s, int c, size_t n) @nogc nothrow;
    int memcmp(const(void)* a, const(void)* b, size_t n) @nogc nothrow;

    void enableSSE() @nogc nothrow;     // mem.s - call first thing in kmain

    void* fastMemcpyNT(void* dest, const(void)* src, size_t size) @nogc nothrow;
}

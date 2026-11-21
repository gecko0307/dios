module object;

// Minimal runtime for user programs (the kernel has its own, in src/object.d).
alias size_t = typeof(int.init.sizeof);
alias ptrdiff_t = typeof(cast(void*)0 - cast(void*)0);
alias string = immutable(char)[];
alias noreturn = typeof(*null);

class Object
{
    void* _vptr;
    void* _monitor;
}

interface Interface { }

struct TypeInfo { }
struct TypeInfo_Class { }

alias ClassInfo = TypeInfo_Class;

extern(C)
{
    bool _xopEquals(const(void)* p1, const(void)* p2) @nogc nothrow { return p1 == p2; }
    int _xopCmp(const(void)* p1, const(void)* p2) @nogc nothrow { return 0; }
    void _d_callinterfacector(void* p) @nogc nothrow {}
    void _d_callinterfacedtor(void* p) @nogc nothrow {}

    // A failed assert ends the program.
    void _d_assert(string file, uint line) @nogc nothrow
    {
        sys_call(0, 134, 0, 0);
        for (;;) {}
    }

    long sys_call(ulong nr, ulong a0, ulong a1, ulong a2) @nogc nothrow;
}

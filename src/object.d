module object;

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
}

extern(C) void _d_assert(string file, uint line) @nogc nothrow
{
}

extern(C)
{
    void _d_callinterfacector(void* p) @nogc nothrow {}
    void _d_callinterfacedtor(void* p) @nogc nothrow {}
}

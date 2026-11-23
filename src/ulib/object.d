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
module object;

import ulib.dios.sys;

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
}

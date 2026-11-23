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
module ulib.dios.mem;

extern(C):

///
void* memset(void* dst, int c, size_t n) @nogc nothrow
{
    ubyte* p = cast(ubyte*)dst;
    for (size_t i = 0; i < n; i++)
        p[i] = cast(ubyte)c;
    return dst;
}

///
void* memcpy(void* dst, const(void)* src, size_t n) @nogc nothrow
{
    ubyte* d = cast(ubyte*)dst;
    const(ubyte)* s = cast(const(ubyte)*)src;
    for (size_t i = 0; i < n; i++)
        d[i] = s[i];
    return dst;
}

///
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

/**
 * Returns 0 if the memory blocks are identical,
 * a negative number if the first differing byte in `vl` is less
 * than the corresponding byte in `vr`, and a positive number if it is greater.
 */
int memcmp(const(void)* vl, const(void)* vr, size_t n) @nogc nothrow
{
    ubyte* l = cast(ubyte*)vl;
    ubyte* r = cast(ubyte*)vr;
    for (; n && *l == *r; n--, l++, r++) {}
    return n ? *l - *r : 0;
}

///
size_t ustrlen(const(char)* s) @nogc nothrow
{
    size_t n = 0;
    while (s[n] != 0)
        n++;
    return n;
}

///
size_t alignUp(size_t value, size_t alignment) @nogc nothrow
{
    return (value + alignment - 1) & ~(alignment - 1);
}

///
size_t alignDown(size_t a, size_t alignment) @nogc nothrow
{
    return a & ~(alignment - 1);
}

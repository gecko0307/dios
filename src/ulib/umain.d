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
module umain;

/*
 * Runtime entry point.
 * Allocates an arguments array and calls compiler-generated `_Dmain`.
 */

import ulib.dios;

private bool isSpace(char c) @nogc nothrow
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

private void skipSpaces(ref const(char)* p) @nogc nothrow
{
    while (*p && isSpace(*p))
        ++p;
}

extern(C) int _Dmain(string[] args) @nogc nothrow;

extern(C) int umain(const(char)* rawArgs) @nogc nothrow
{
    const(char)* p = rawArgs;

    // First pass: count arguments and calculate string storage size.
    size_t argc = 0;
    size_t charsSize = 0;

    while (true)
    {
        skipSpaces(p);
        if (!*p)
            break;
        ++argc;
        while (*p && !isSpace(*p))
        {
            ++charsSize;
            ++p;
        }
    }

    if (argc == 0)
    {
        string[] empty;
        return _Dmain(empty);
    }

    // Allocate descriptors and string data in one block.
    size_t arraySize = argc * string.sizeof;
    void* block = umalloc(arraySize + charsSize);

    if (!block)
        return -1;

    string[] argv = (cast(string*)block)[0..argc];

    char* dst = cast(char*)block + arraySize;
    p = rawArgs;

    // Second pass: populate the array.
    size_t index = 0;

    while (true)
    {
        skipSpaces(p);
        if (!*p)
            break;
        char* start = dst;
        while (*p && !isSpace(*p))
        {
            *dst++ = *p++;
        }
        size_t len = cast(size_t)(dst - start);
        *dst++ = '\0';
        argv[index++] = cast(string)start[0..len];
    }

    int result = _Dmain(argv);

    ufree(block);

    return result;
}

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
module brktest;

import dios.ulib;

extern(C) int umain(const(char)* args) @nogc nothrow
{
    void* initial = ubrk(null);

    uputs("Initial break: ");
    uputhex(cast(ulong)initial);
    uputc('\n');

    // Expand by 3 pages.
    void* expanded = ubrk(cast(void*)(cast(ulong)initial + 3 * 4096));

    if (expanded is null)
    {
        uputs("brk expansion failed\n");
        uexit(1);
    }

    uputs("Expanded break: ");
    uputhex(cast(ulong)expanded);
    uputc('\n');

    // Write into every allocated page.
    ubyte* p = cast(ubyte*)initial;

    p[0] = 0x12;
    p[4096] = 0x34;
    p[8192] = 0x56;

    uputs("Memory test: ");
    uputhex(p[0]);
    uputc(' ');
    uputhex(p[4096]);
    uputc(' ');
    uputhex(p[8192]);
    uputc('\n');

    // Shrink back to the initial break.
    void* restored = ubrk(initial);

    if (restored != initial)
    {
        uputs("brk shrink failed\n");
        uexit(2);
    }

    uputs("Heap restored\n");
    return 0;
}

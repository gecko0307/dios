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
module main;

import ulib.dios;

int main(string[] args)
{
    // calloc: memory must be zeroed
    ubyte* a = cast(ubyte*)ucalloc(32, 1);

    if (a is null)
    {
        uputs("calloc failed\n");
        uexit(1);
    }

    bool zeroed = true;

    for (size_t i = 0; i < 32; i++)
        if (a[i] != 0)
            zeroed = false;

    if (!zeroed)
    {
        uputs("calloc zeroing failed\n");
        uexit(2);
    }

    uputs("calloc: OK\n");

    // Force realloc to move the allocation.
    void* b = umalloc(32);

    if (b is null)
    {
        uputs("malloc failed\n");
        uexit(3);
    }

    for (size_t i = 0; i < 32; i++)
        a[i] = cast(ubyte)(i + 1);

    ubyte* resized = cast(ubyte*)urealloc(a, 128);

    if (resized is null)
    {
        uputs("realloc failed\n");
        uexit(4);
    }

    for (size_t i = 0; i < 32; i++)
    {
        if (resized[i] != i + 1)
        {
            uputs("realloc data corruption\n");
            uexit(5);
        }
    }

    uputs("realloc: OK\n");

    // Shrink
    resized = cast(ubyte*)urealloc(resized, 16);

    if (resized is null)
    {
        uputs("realloc shrink failed\n");
        uexit(6);
    }

    uputs("realloc shrink: OK\n");

    ufree(b);
    ufree(resized);

    UHeapStats stats;

    if (!uheapGetStats(&stats))
    {
        uputs("heap stats failed\n");
        uexit(7);
    }

    uputs("Heap size: ");
    uputu(stats.heapSize);
    uputs("\nAllocated: ");
    uputu(stats.allocatedBytes);
    uputs("\nFree: ");
    uputu(stats.freeBytes);
    uputs("\nBlocks: ");
    uputu(stats.allocatedBlocks + stats.freeBlocks);
    uputs("\n");
    
    int[6] a1 = [0, 1, 2, 3, 4, 5];
    int[6] a2 = [5, 4, 3, 2, 1, 0];
    uputu(memcmp(a1.ptr, a2.ptr, 6) == 0);
    uputs("\n");

    uputs("All tests passed\n");
    return 0;
}

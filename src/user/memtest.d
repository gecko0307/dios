module memtest;

import ulib;

extern(C) int umain(const(char)* args) @nogc nothrow
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

    uputs("All tests passed\n");
    return 0;
}

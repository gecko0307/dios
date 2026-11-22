module memtest;

import ulib;

extern(C) int umain(const(char)* args) @nogc nothrow
{
    uputs("Allocating blocks...\n");

    void* a = umalloc(100);
    void* b = umalloc(100);
    void* c = umalloc(100);

    if (a is null || b is null || c is null)
    {
        uputs("Allocation failed\n");
        return 1;
    }

    uputs("A: ");
    uputhex(cast(ulong)a);
    uputs("\nB: ");
    uputhex(cast(ulong)b);
    uputs("\nC: ");
    uputhex(cast(ulong)c);
    uputs("\n");

    // Write some data.
    (cast(ubyte*)a)[0] = 0x11;
    (cast(ubyte*)b)[0] = 0x22;
    (cast(ubyte*)c)[0] = 0x33;

    uputs("Freeing A and B...\n");

    ufree(a);
    ufree(b);

    // The two adjacent free blocks should be merged.
    void* d = umalloc(180);

    if (d != a)
    {
        uputs("Block reuse/coalescing failed\n");
        return 2;
    }

    uputs("Merged block reused: ");
    uputhex(cast(ulong)d);
    uputs("\n");

    if ((cast(ubyte*)c)[0] != 0x33)
    {
        uputs("Data corruption!\n");
        return 3;
    }

    ufree(c);
    ufree(d);

    uputs("All tests passed\n");
    return 0;
}

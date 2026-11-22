module brktest;

import ulib;

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

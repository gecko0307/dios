module count;

import ulib;

// Counts once a second. Ctrl+C stops it (the kernel handles that).
extern(C) int umain(const(char)* args) @nogc nothrow
{
    uint n = 10;
    if (args[0] >= '0' && args[0] <= '9')
    {
        n = 0;
        for (const(char)* p = args; *p >= '0' && *p <= '9'; p++)
            n = n * 10 + (*p - '0');
    }

    uputs("Counting to ");
    uputu(n);
    uputs(", Ctrl+C to stop.\n");
    for (uint i = 1; i <= n; i++)
    {
        usleep(1000);
        uputu(i);
        uputs("\n");
    }
    uputs("Done.\n");
    return 0;
}

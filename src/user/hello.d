module hello;

import ulib;

extern(C) int umain(const(char)* args) @nogc nothrow
{
    uputs("Hello from user mode (ring 3)!\n");
    uputs("Arguments: ");
    if (args[0] == 0)
        uputs("(none)");
    else
        uputs(args);
    uputs("\n");
    uputs("Stack is near ");
    char marker;
    uputhex(cast(ulong)&marker);
    uputs(", uptime ");
    uputu(uticks() / 1000);
    uputs(" s\n");
    return 0;
}

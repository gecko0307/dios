module hello;

import ulib;

extern(C) int umain(const(char)* args) @nogc nothrow
{
    uputs("Hello, World!\n");
    uputs("Arguments: ");
    if (args[0] == 0)
        uputs("(none)");
    else
        uputs(args);
    uputs("\n");
    return 0;
}

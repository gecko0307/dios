module core.stdio;

import core.stdarg;
import core.console;

extern(C):

void kprintf(string fmt, ...) @nogc nothrow
{
    va_list ap;
    va_start!(string)(ap, fmt);
    Console.writef(fmt, ap);
    va_end(ap);
}

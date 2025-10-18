module stdio;

import core.stdc.stdarg;
import console;

extern(C):

/*
// VGA text mode version
void kprintf(string fmt, ...) @nogc nothrow
{
    va_list ap;
    va_start!(string)(ap, fmt);
    Console.writef(fmt, ap);
    va_end(ap);
}
*/

void kprintf(string fmt, ...) @nogc nothrow
{
    va_list ap;
    va_start!(string)(ap, fmt);
    consolePrintStringFmt(fmt, ap);
    va_end(ap);
}

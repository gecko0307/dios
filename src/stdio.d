module stdio;

import core.stdc.stdarg;
import console;

enum StdioMode
{
    VGATextMode,
    Framebuffer
}

__gshared StdioMode stdioMode;

extern(C):

void kprintf(string fmt, ...) @nogc nothrow
{
    va_list ap;
    va_start!(string)(ap, fmt);
    if (stdioMode == StdioMode.Framebuffer)
        consolePrintStringFmt(fmt, ap);
    else if (stdioMode == StdioMode.VGATextMode)
        VGAConsole.writef(fmt, ap);
    va_end(ap);
}

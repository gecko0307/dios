module dios.core.stdio;

import dios.core.console;
import dios.core.gfx;
import core.stdc.stdarg;

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
    {
        consolePrintStringFmt(fmt, ap);
        gfxPresent(); // cheap: copies only the characters just printed
    }
    else if (stdioMode == StdioMode.VGATextMode)
        VGAConsole.writef(fmt, ap);
    va_end(ap);
}

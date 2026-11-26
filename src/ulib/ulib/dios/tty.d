/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/
module ulib.dios.tty;

import ulib.dios.sys;

extern(C):

// Terminals: programs that show the standard output of other programs.

/// Creates an output channel that you read. Returns its id (> 0), or -1 if there is no room for another one.
int uttyCreate() @nogc nothrow
{
    return cast(int)sys_call(SYS_TTY_CREATE, 0, 0, 0);
}

/**
 * Takes up to n bytes that programs wrote to your channel. Does not wait: returns the number of
 * bytes (0 = nothing there right now), or -1 if the channel is not yours or is gone.
 * The bytes are raw: '\n', 8 (backspace) and 12 (clear) are yours to interpret.
 */
long uttyRead(int tty, void* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_TTY_READ, cast(ulong)tty, cast(ulong)buf, n);
}

/// Number of programs that are writing to your channel now (they end by themselves), or -1 on error.
int uttyWriters(int tty) @nogc nothrow
{
    return cast(int)sys_call(SYS_TTY_STAT, cast(ulong)tty, 0, 0);
}

/// Closes your channel. Programs still writing to it lose their output (their writes fail). It is also closed when you exit.
int uttyClose(int tty) @nogc nothrow
{
    return cast(int)sys_call(SYS_TTY_CLOSE, cast(ulong)tty, 0, 0);
}

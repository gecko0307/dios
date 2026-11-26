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
module main;

import ulib.dios;

enum size_t PATH_MAX = 256;
enum size_t CHUNK = 16384;

bool sameName(const(char)* a, const(char)* b) @nogc nothrow
{
    for (;; a++, b++)
    {
        char x = *a;
        char y = *b;
        if (x >= 'A' && x <= 'Z')
            x += 'a' - 'A';
        if (y >= 'A' && y <= 'Z')
            y += 'a' - 'A';
        if (x != y)
            return false;
        if (x == 0)
            return true;
    }
}

// cp SOURCE DEST - copy a file. DEST may be a directory.
int main(string[] args)
{
    if (args.length != 2)
    {
        uputs("Usage: cp SOURCE DEST   (DEST may be a directory)\n");
        return 1;
    }
    const(char)* src = args[0].ptr;

    char[PATH_MAX] target;
    utargetpath(src, args[1].ptr, target.ptr, target.length);

    UStat st;
    if (ustat(src, &st) < 0 || st.isDir)
    {
        uprintf("cp: %s: not a file\n", src);
        return 1;
    }

    // Opening the destination empties it: it must not be the source itself. (Names are compared
    // without regard to case, as the volumes do; "A" and "a" on /home would be refused too.)
    char[PATH_MAX] a;
    char[PATH_MAX] b;
    if (urealpath(src, a.ptr, a.length) >= 0 && urealpath(target.ptr, b.ptr, b.length) >= 0 &&
        sameName(a.ptr, b.ptr))
    {
        uprintf("cp: %s and %s are the same file\n", src, target.ptr);
        return 1;
    }

    int in_ = uopen(src, O_RDONLY);
    if (in_ < 0)
    {
        uperror("cp", src, in_);
        return 1;
    }
    int out_ = uopen(target.ptr, O_WRONLY | O_CREATE | O_TRUNC);
    if (out_ < 0)
    {
        uperror("cp", target.ptr, out_);
        uclose(in_);
        return 1;
    }

    ubyte[CHUNK] buf;
    int status = 0;
    for (;;)
    {
        long got = uread(in_, buf.ptr, buf.length);
        if (got == 0)
            break;
        if (got < 0)
        {
            uprintf("cp: read error in %s\n", src);
            status = 1;
            break;
        }
        long w = ufwrite(out_, buf.ptr, cast(size_t)got);
        if (w != got)
        {
            uperror("cp", target.ptr, w < 0 ? cast(int)w : UERR_NO_SPACE);
            status = 1;
            break;
        }
    }

    uclose(out_);
    uclose(in_);
    return status;
}

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

void putPad(ulong v, uint width)
{
    char[20] d;
    uint k = 20;
    do
    {
        d[--k] = cast(char)('0' + v % 10);
        v /= 10;
    }
    while (v != 0);

    for (uint i = 20 - k; i < width; i++)
        uputc(' ');

    uwrite(d.ptr + k, 20 - k);
}

void putTwo(uint v)
{
    uputc(cast(char)('0' + (v / 10) % 10));
    uputc(cast(char)('0' + v % 10));
}

// dir [PATH] - list a directory
int main(string[] args)
{
    string path = args.length == 0 ? "." : args[0];
    
    UStat st;
    if (ustat(path.ptr, &st) < 0)
    {
        uputs("dir: not found: ");
        uputs(path.ptr);
        uputs("\n");
        return 1;
    }

    if (!st.isDir)
    {
        putPad(st.size, 10);
        uputs("  ");
        uputs(path.ptr);
        uputs("\n");
        return 0;
    }

    int fd = uopen(path.ptr);
    if (fd < 0)
    {
        uputs("dir: cannot open\n");
        return 1;
    }

    UDirent e;
    uint files = 0, dirs = 0;

    while (ureaddir(fd, &e) > 0)
    {
        uint t = e.mtime;

        putPad(1980 + (t >> 25), 4);
        uputc('-');
        putTwo((t >> 21) & 0xF);
        uputc('-');
        putTwo((t >> 16) & 0x1F);
        uputs("  ");

        if (e.isDir)
        {
            uputs("     <DIR>  ");
            dirs++;
        }
        else
        {
            putPad(e.size, 10);
            uputs("  ");
            files++;
        }

        uputs(e.name.ptr);
        uputc('\n');
    }

    uclose(fd);

    putPad(files, 1);
    uputs(" file(s), ");
    putPad(dirs, 1);
    uputs(" dir(s)\n");

    return 0;
}

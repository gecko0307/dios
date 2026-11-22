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

// file FILE [OFFSET] - print a text file, optionally starting at a byte offset
int main(string[] args)
{
    if (args.length == 0)
    {
        uputs("usage: file FILE [OFFSET]\n");
        return 1;
    }

    string name = args[0];

    long offset = 0;

    if (args.length > 1)
    {
        string s = args[1];

        if (s.length == 0)
        {
            uputs("file: invalid offset\n");
            return 1;
        }

        foreach (char c; s)
        {
            if (c < '0' || c > '9')
            {
                uputs("file: invalid offset\n");
                return 1;
            }

            int digit = c - '0';

            if (offset > (long.max - digit) / 10)
            {
                uputs("file: invalid offset\n");
                return 1;
            }

            offset = offset * 10 + digit;
        }
    }

    int fd = uopen(name.ptr);

    if (fd < 0)
    {
        uputs("file: cannot open ");
        uputs(name.ptr);
        uputs("\n");
        return 1;
    }

    if (offset != 0 && useek(fd, offset, SEEK_SET) < 0)
    {
        uputs("file: bad offset\n");
        uclose(fd);
        return 1;
    }

    char[512] buf;

    for (;;)
    {
        long got = uread(fd, buf.ptr, buf.length);

        if (got < 0)
        {
            uputs("\nfile: read error\n");
            uclose(fd);
            return 1;
        }

        if (got == 0)
            break;

        uwrite(buf.ptr, cast(size_t)got);
    }

    uclose(fd);
    uputc('\n');

    return 0;
}

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

enum size_t TEXT_MAX = 300;     // the argument string of a program is shorter than 256 bytes anyway

// append FILE TEXT - add TEXT and a newline to the end of the file (it is created if needed)
// The words of TEXT are joined with single spaces (the program gets its arguments split at blanks).
int main(string[] args)
{
    if (args.length < 1)
    {
        uputs("Usage: append FILE TEXT\n");
        return 1;
    }

    char[TEXT_MAX] text;
    size_t len = 0;
    for (size_t i = 1; i < args.length; i++)
    {
        if (len + args[i].length + 2 > text.length)
        {
            uputs("append: text too long\n");
            return 1;
        }
        if (i > 1)
            text[len++] = ' ';
        for (size_t k = 0; k < args[i].length; k++)
            text[len++] = args[i][k];
    }
    text[len++] = '\n';

    int fd = uopen(args[0].ptr, O_WRONLY | O_CREATE | O_APPEND);
    if (fd < 0)
    {
        uperror("append", args[0].ptr, fd);
        return 1;
    }
    long w = ufwrite(fd, text.ptr, len);
    uclose(fd);
    if (w != cast(long)len)
    {
        uperror("append", args[0].ptr, w < 0 ? cast(int)w : UERR_NO_SPACE);
        return 1;
    }
    return 0;
}

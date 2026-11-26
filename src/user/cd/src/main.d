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

/**
 * cd [DIR] - change the current directory (no argument: the root).
 *
 * The current directory belongs to the whole system, not to a program, so this works as a
 * separate program: the change is still there for the kernel shell and for the next programs.
 */
int main(string[] args)
{
    if (args.length > 1)
    {
        uputs("cd: too many arguments\n");
        return 1;
    }

    string path = args.length == 0 ? "/" : args[0];

    int r = uchdir(path.ptr);
    if (r == 0)
        return 0;

    uputs("cd: ");
    uputs(path.ptr);
    uputs(r == UERR_NOT_DIR ? ": not a directory\n" : ": no such directory\n");
    return 1;
}

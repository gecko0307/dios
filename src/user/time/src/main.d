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

/*
 * time - a program that prints current date and time.
 * `time -u` prints time since the system boot.
 */

import ulib.dios;

int main(string[] args)
{
    if (args.length > 0)
    {
        if (args[0] == "-u")
        {
            ulong ms = uticks();
            ulong seconds = ms / 1000;
            ulong days = seconds / 86400;
            ulong hours = (seconds / 3600) % 24;
            ulong minutes = (seconds / 60) % 60;
            ulong secs = seconds % 60;
            uprintf("Uptime: %llu day(s), %llu hour(s), %llu minute(s), %llu second(s)\n",
                days, hours, minutes, secs);
            return 0;
        }
    }

    DateTime dt;
    udatetime(&dt);
    uprintf("%02d.%02d.%d %02d:%02d:%02d\n",
        dt.day, dt.month, dt.year,
        dt.hour, dt.minute, dt.second);
    return 0;
}

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

bool parseDuration(string str, out ulong milliseconds)
{
    milliseconds = 0;

    if (str.length == 0)
        return false;

    ulong value = 0;
    size_t i = 0;

    while (str[i] >= '0' && str[i] <= '9')
    {
        ulong digit = cast(ulong)(str[i] - '0');
        if (value > (ulong.max - digit) / 10)
            return false;
        value = value * 10 + digit;
        i++;
    }

    if (i == 0 || value == 0)
        return false;

    ulong multiplier;

    switch (str[i])
    {
        case 's': multiplier = 1000; break;
        case 'm': multiplier = 60 * 1000; break;
        case 'h': multiplier = 60 * 60 * 1000; break;
        default: return false;
    }

    if (str[i + 1] != '\0')
        return false;

    if (value > ulong.max / multiplier)
        return false;

    milliseconds = value * multiplier;
    return true;
}

void printUsage()
{
    uprintf("Usage: timer.elf Ns|Nm|Nh\n");
    uprintf(" N - time in seconds, minutes, or hours\n");
}

int main(string[] args)
{
    if (args.length == 0)
    {
        printUsage();
        return 0;
    }
    
    ulong durationMs = 0;
    if (!parseDuration(args[0], durationMs))
    {
        printUsage();
        return 0;
    }
    
    if (durationMs > 0)
    {
        DateTime dt;
        udatetime(&dt);
        uprintf("Timer started at %d:%d:%d\n", dt.hour, dt.minute, dt.second);
        
        usleep(durationMs);
        uprintf("Time is up!\n");
    }
    else
        printUsage();
    
    return 0;
}

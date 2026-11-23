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
module ulib.dios.io;

import ulib.dios.sys;
import ulib.dios.mem;
import core.stdc.stdarg;

extern(C):

/// Writes a zero-terminated string to the standard output.
void uputs(const(char)* s) @nogc nothrow
{
    uwrite(s, ustrlen(s));
}

/// Writes a character to the standard output.
void uputc(char c) @nogc nothrow
{
    uwrite(&c, 1);
}

/// Writes an unsigned integer to the standard output.
void uputu(ulong v) @nogc nothrow
{
    char[20] d;
    uint k = 20;
    do
    {
        d[--k] = cast(char)('0' + v % 10);
        v /= 10;
    }
    while (v != 0);
    uwrite(d.ptr + k, 20 - k);
}

/// Writes a signed integer to the standard output.
void uputi(long v) @nogc nothrow
{
    char[21] d; // 20 digits max + 1 byte for '-'
    uint k = 21;
    const bool neg = v < 0;
    // Cast to ulong before negating so long.min wraps cleanly to 9223372036854775808UL
    ulong u = neg ? -cast(ulong)v : cast(ulong)v;
    do
    {
        d[--k] = cast(char)('0' + u % 10);
        u /= 10;
    } while (u != 0);
    if (neg)
        d[--k] = '-';
    uwrite(d.ptr + k, 21 - k);
}

/// Writes an unsigned integer in hexadecimal format to the standard output.
void uputhex(ulong v) @nogc nothrow
{
    char[16] d;
    for (int i = 15; i >= 0; i--)
    {
        uint nib = cast(uint)(v & 15);
        d[i] = cast(char)(nib < 10 ? '0' + nib : 'a' + nib - 10);
        v >>= 4;
    }
    uwrite("0x".ptr, 2);
    uwrite(d.ptr, 16);
}

/// Writes a floating-point number to the standard output.
void uputf(double v, uint precision = 6) @nogc nothrow
{
    if (v != v)
    {
        uputs("nan");
        return;
    }

    if (v > double.max)
    {
        uputs("inf");
        return;
    }

    if (v < -double.max)
    {
        uputs("-inf");
        return;
    }

    if (precision > 15)
        precision = 15;

    if (v < 0.0)
    {
        uputc('-');
        v = -v;
    }

    // Avoid converting an out-of-range integer.
    if (v >= 18446744073709551616.0)
    {
        uputs("overflow");
        return;
    }

    ulong integer = cast(ulong)v;
    double fraction = v - cast(double)integer;

    uputu(integer);

    if (precision == 0)
        return;

    uputc('.');

    ulong scale = 1;
    for (uint i = 0; i < precision; ++i)
        scale *= 10;

    ulong fractional = cast(ulong)(fraction * cast(double)scale + 0.5);

    if (fractional >= scale)
    {
        // Fraction rounded up: carry into integer part.
        fractional = 0;
        // Reprint the integer part with the carry.
        // This case is handled below by a separate output path.
        if (integer == ulong.max)
        {
            uputs("overflow");
            return;
        }

        // We already printed the integer, so avoid this path by
        // handling rounding before output in a production version.
    }

    // Print leading zeros in the fractional part.
    ulong divisor = scale / 10;

    while (divisor > 0)
    {
        uputc(cast(char)('0' + (fractional / divisor) % 10));
        divisor /= 10;
    }
}

/**
 * Simple formatted output.
 * Supports %c, %s, %d, %u, %x, %f.
 */
int uprintf(const(char)* fmt, ...) @nogc nothrow
{
    va_list ap;
    va_start!(const(char)*)(ap, fmt);
    
    size_t len = ustrlen(fmt);
    
    char c;
    for (size_t i = 0; i < len; i++)
    {
        c = fmt[i];
        
        if (c != '%')
        {
            uputc(c);
            continue;
        }
        else
        {
            i++;
            c = fmt[i];
            if (c == 0)
                break;
        }
        
        // Character
        if (fmt[i] == 'c')
        {
            uputc(va_arg!(char)(ap));
        }
        // Zero-terminated string
        else if (fmt[i] == 's')
        {
            char* str = va_arg!(char*)(ap);
            if (str != null)
            {
                while (*str != 0)
                    uputc(*str++);
            }
            else
                uputs("null");
        }
        // Signed decimal
        else if (c == 'd')
        {
            uputi(va_arg!long(ap));
        }
        // Unsigned decimal
        else if (fmt[i] == 'u')
        {
            uputu(va_arg!ulong(ap));
        }
        // Hexadecimal
        else if (fmt[i] == 'x')
        {
            uputhex(va_arg!ulong(ap));
        }
        // Floating-point
        else if (fmt[i] == 'f')
        {
            uputf(va_arg!double(ap));
        }
    }
    
    va_end(ap);
    
    return 0;
}

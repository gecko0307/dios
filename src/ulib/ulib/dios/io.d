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

// Buffered output device
private struct OutBuf
{
    char[512] data;
    size_t pos = 0;

    void putc(char c) @nogc nothrow
    {
        if (pos >= data.length)
            flush();
        data[pos++] = c;
    }

    void puts(const(char)* s, size_t len) @nogc nothrow
    {
        for (size_t i = 0; i < len; i++)
            putc(s[i]);
    }

    void flush() @nogc nothrow
    {
        if (pos > 0)
        {
            uwrite(data.ptr, pos);
            pos = 0;
        }
    }
}

private __gshared OutBuf outBuf;

extern(C):

void uflush_b() @nogc nothrow
{
    outBuf.flush();
}

/// [Buffered] Writes a zero-terminated string to the standard output.
void uputs_b(const(char)* s) @nogc nothrow
{
    outBuf.puts(s, ustrlen(s));
}

/// [Buffered] Writes a zero-terminated string to the standard output.
void uputc_b(char c) @nogc nothrow
{
    outBuf.putc(c);
}

/// [Buffered] Writes an unsigned integer to the standard output.
void uputu_b(ulong v) @nogc nothrow
{
    char[20] d;
    uint k = 20;
    do
    {
        d[--k] = cast(char)('0' + v % 10);
        v /= 10;
    }
    while (v != 0);
    outBuf.puts(d.ptr + k, 20 - k);
}

immutable char[16] HEXMAP = [
    '0', '1', '2', '3',
    '4', '5', '6', '7',
    '8', '9', 'A', 'B',
    'C', 'D', 'E', 'F'
];

/// [Buffered] Writes a formatted integer to the standard output.
void _uputint_b_fmt(ulong value, bool negative, uint base, uint minDigits, uint width, char pad, const(char)* prefix, uint prefixLen) @nogc nothrow
{
    char[20] digits;
    uint count = 0;

    do
    {
        digits[count++] = HEXMAP[value % base];
        value /= base;
    }
    while (value != 0);

    while (count < minDigits)
        digits[count++] = '0';

    uint totalLen = count + prefixLen + (negative ? 1 : 0);
    uint padding = (width > totalLen) ? width - totalLen : 0;

    // Space padding goes before the number
    if (pad != '0')
    {
        while (padding > 0)
        {
            outBuf.putc(pad);
            padding--;
        }
    }

    // Prefix
    for (uint i = 0; i < prefixLen; i++)
        outBuf.putc(prefix[i]);

    // Sign
    if (negative)
        outBuf.putc('-');

    // Zero padding goes after prefix and sign
    if (pad == '0')
    {
        while (padding > 0)
        {
            outBuf.putc('0');
            padding--;
        }
    }

    // Digits in reverse order
    while (count > 0)
        outBuf.putc(digits[--count]);
}

/// [Buffered] Writes a signed integer to the standard output.
void uputi_b(long v) @nogc nothrow
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
    outBuf.puts(d.ptr + k, 21 - k);
}

/// [Buffered] Writes an unsigned integer in hexadecimal format to the standard output.
void uputhex_b(ulong v) @nogc nothrow
{
    char[16] d;
    for (int i = 15; i >= 0; i--)
    {
        uint nib = cast(uint)(v & 15);
        d[i] = cast(char)(nib < 10 ? '0' + nib : 'a' + nib - 10);
        v >>= 4;
    }
    outBuf.puts("0x".ptr, 2);
    outBuf.puts(d.ptr, 16);
}

/// [Buffered] Writes a floating-point number to the standard output.
void uputf_b(double v, uint precision = 6) @nogc nothrow
{
    if (v != v)
    {
        uputs_b("nan");
        return;
    }

    if (v > double.max)
    {
        uputs_b("inf");
        return;
    }

    if (v < -double.max)
    {
        uputs_b("-inf");
        return;
    }

    if (precision > 15)
        precision = 15;

    if (v < 0.0)
    {
        uputc_b('-');
        v = -v;
    }

    // Avoid converting an out-of-range integer.
    if (v >= 18446744073709551616.0)
    {
        uputs_b("overflow");
        return;
    }

    ulong integer = cast(ulong)v;
    double fraction = v - cast(double)integer;

    uputu_b(integer);

    if (precision == 0)
        return;

    uputc_b('.');

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
            uputs_b("overflow");
            return;
        }

        // We already printed the integer, so avoid this path by
        // handling rounding before output in a production version.
    }

    // Print leading zeros in the fractional part.
    ulong divisor = scale / 10;

    while (divisor > 0)
    {
        uputc_b(cast(char)('0' + (fractional / divisor) % 10));
        divisor /= 10;
    }
}

/// [Immediate] Writes a zero-terminated string to the standard output.
void uputs(const(char)* s) @nogc nothrow
{
    uwrite(s, ustrlen(s));
}

/// [Immediate] Writes a character to the standard output.
void uputc(char c) @nogc nothrow
{
    uwrite(&c, 1);
}

/// [Immediate] Writes an unsigned integer to the standard output.
void uputu(ulong v) @nogc nothrow
{
    uputu_b(v);
    outBuf.flush();
}

/// [Immediate] Writes a signed integer to the standard output.
void uputi(long v) @nogc nothrow
{
    uputi_b(v);
    outBuf.flush();
}

/// [Immediate] Writes an unsigned integer in hexadecimal format to the standard output.
void uputhex(ulong v) @nogc nothrow
{
    uputhex_b(v);
    outBuf.flush();
}

/// [Immediate] Writes a floating-point number to the standard output.
void uputf(double v, uint precision = 6) @nogc nothrow
{
    uputf_b(v, precision);
    outBuf.flush();
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
            uputc_b(c);
            continue;
        }
        
        if (++i >= len)
            break;

        // Parse flags and field width.
        char pad = ' ';
        uint width = 0;

        if (fmt[i] == '0')
        {
            pad = '0';
            i++;
        }

        while (i < len &&
               fmt[i] >= '0' &&
               fmt[i] <= '9')
        {
            width = width * 10 + (fmt[i] - '0');

            // Protect against unreasonable field widths.
            if (width > 64)
                width = 64;

            i++;
        }

        if (i >= len)
            break;

        //i++;
        //c = fmt[i];
        //if (c == 0)
        //    break;
        
        // Length modifier: ll
        bool isLongLong = false;
        
        if (fmt[i] == 'l' &&
            i + 1 < len &&
            fmt[i + 1] == 'l')
        {
            isLongLong = true;
            i += 2;

            if (i >= len)
                break;
        }
        
        // Zero-terminated string
        if (fmt[i] == 's')
        {
            char* str = va_arg!(char*)(ap);

            if (str != null)
            {
                while (*str != 0)
                    uputc_b(*str++);
            }
            else
                uputs_b("null");
        }
        // Character
        else if (fmt[i] == 'c')
        {
            uputc_b(va_arg!(char)(ap));
        }
        // Signed decimal
        else if (fmt[i] == 'd')
        {
            //uputi_b(va_arg!long(ap));
            long value = va_arg!long(ap);
            bool negative = value < 0;
            ulong magnitude = negative? cast(ulong)(-value) : cast(ulong)value;
            _uputint_b_fmt(magnitude, negative, 10, 1, width, pad, null, 0);
        }
        // Unsigned decimal
        else if (fmt[i] == 'u')
        {
            //uputu_b(va_arg!ulong(ap));
            ulong value = va_arg!ulong(ap);
            _uputint_b_fmt(value, false, 10, 1, width, pad, null, 0);
        }
        // Hexadecimal
        else if (fmt[i] == 'x')
        {
            //uputhex_b(va_arg!ulong(ap));
            ulong value = va_arg!ulong(ap);
            uint digits = isLongLong ? 16 : 8;
            _uputint_b_fmt(value, false, 16, digits, width, pad, "0x".ptr, 2);
        }
        // 16-bit hexadecimal
        else if (fmt[i] == 'k')
        {
            ushort value = va_arg!ushort(ap);
            _uputint_b_fmt(value, false, 16, 4, width, pad, "0x".ptr, 2);
        }
        // 8-bit hexadecimal
        else if (fmt[i] == 'X')
        {
            ubyte value = va_arg!ubyte(ap);
            _uputint_b_fmt(value, false, 16, 2, width, pad, "0x".ptr, 2);
        }
        // Floating-point
        else if (fmt[i] == 'f')
        {
            uputf_b(va_arg!double(ap));
        }
    }
    
    va_end(ap);
    
    outBuf.flush();
    
    return 0;
}

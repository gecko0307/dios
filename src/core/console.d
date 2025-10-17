module core.console;

import core.vga;
import core.stdarg;

extern(C):

enum ConsoleColor
{
    // Background and Foreground
    Black = 0,
    Navy = 1,
    Green = 2,
    Teal = 3,
    Maroon = 4,
    Purple = 5,
    Brown = 6,
    Silver = 7,

    // Foreground Only
    Grey = 8,
    Blue = 9,
    Lime = 10,
    Aqua = 11,
    Red = 12,
    Pink = 13,
    Yellow = 14,
    White = 15
}

struct Console
{
    public static:

    const char[] hexmap = 
    [
        '0', '1', '2', '3', 
        '4', '5', '6', '7', 
        '8', '9', 'A', 'B', 
        'C', 'D', 'E', 'F'
    ];

    void init() @nogc nothrow
    {
        VGAText.clearScreen();
        VGAText.setColors(ConsoleColor.Silver, ConsoleColor.Black);
    }

    void writef(string fmt, va_list ap) @nogc nothrow
    {
        uint f;
        for (int i = 0; i < fmt.length; i++)
        {
            char c = fmt[i];
            if (c == '%')
            {
                if (++i >= fmt.length)
                    break;

                if (fmt[i] == 's')
                {
                    char* t = va_arg!(char*)(ap);
                    for(char n = *t; n != 0; t++)
                    {
                        n = *t;
                        VGAText.putChar(n);
                    }
                }
                else if (fmt[i] == 'c')
                {
                    VGAText.putChar(va_arg!(char)(ap));
                }
                else if (fmt[i] == 'x')
                {
                    uint u = va_arg!(uint)(ap);
                    VGAText.putString("0x");
                    char[8] digits;
                    for (int j = 7; j >= 0; j--)
                    {
                        digits[j] = hexmap[u & 0x0F];
                        u >>= 4;
                    }
                    foreach(char d; digits)
                        VGAText.putChar(d);
                }
                else if (fmt[i] == 'k')
                {
                    ushort u = va_arg!(ushort)(ap);
                    VGAText.putString("0x");
                    char[4] digits;
                    for (int j = 3; j >= 0; j--)
                    {
                        digits[j] = hexmap[u & 0x0F];
                        u >>= 4;
                    }
                    foreach(char d; digits)
                        VGAText.putChar(d);
                }
                else if (fmt[i] == 'd')
                {
                    //case 'd': // signed integer
                        int w = va_arg!(int)(ap);
                        if (w < 0)
                        {
                            f = -w;
                            VGAText.putChar('-');
                        }
                        else
                        {
                            f = w;
                        }
                        goto u2;
                }
                else if (fmt[i] == 'u')
                {
                    f = va_arg!(uint)(ap);
                    u2:
                    {
                        char[10] d;
                        int k = 9;
                        do
                        {
                            d[k] = (f % 10) + '0';
                            f /= 10;
                            k--;
                        }
                        while(f && k >= 0);
                        while(++k < 10)
                        {
                            VGAText.putChar(d[k]);
                        }
                    }
                }
                else if (fmt[i] == 'X')
                {
                    ubyte b = va_arg!(ubyte)(ap);
                    VGAText.putString("0x");
                    VGAText.putChar(hexmap[(b & 0xF0) >> 4]);
                    VGAText.putChar(hexmap[b & 0x0F]);
                }
                else
                {
                    VGAText.putChar(fmt[i]);
                }
            }
            else
            {
                VGAText.putChar(c);
            }
        }
    }
}


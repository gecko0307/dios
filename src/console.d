module console;

import core.vga;
import core.framebuffer;
import core.stdc.stdarg;
import font;

struct VGAConsole
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
        VGAText.setColors(VGAColor.Silver, VGAColor.Black);
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

struct ConsoleState
{
    Framebuffer* fb;
    uint x;
    uint y;
    uint width;
    uint height;
    uint print_x;
    uint print_y;
    uint h_stride;
    uint v_stride;
    uint clear_color;
}

__gshared ConsoleState console;

extern(C):

ConsoleState* consoleInit(Framebuffer* fb, uint x, uint y) @nogc nothrow
{
    console.fb = fb;
    console.x = x;
    console.y = y;
    console.width = fb.width - x - 16;
    console.height = CHAR_HEIGHT;
    console.print_x = 0;
    console.print_y = 0;
    console.clear_color = 0x000000AA;
    console.h_stride = CHAR_WIDTH - 2;
    console.v_stride = CHAR_HEIGHT;
    
    uint numPixels = fb.height * fb.width;
    for (uint i = 0; i < numPixels; i++)
        console.fb.ptr[i] = console.clear_color;
    
    return &console;
}

void consoleBlitTo(Framebuffer* fb) @nogc nothrow
{
    uint baseX = console.x;
    uint baseY = console.y;
    
    for (uint y = 0; y < console.fb.height; y++)
    {
        if (baseY + y >= fb.height)
            break;
        
        for (uint x = 0; x < console.fb.width; x++)
        {
            if (baseX + x >= fb.width)
                break;
            
            uint offset = (baseY + y) * (console.fb.pitch / console.fb.bytesPerPixel) + (baseX + x);
            fb.ptr[offset] = console.fb.ptr[offset];
        }
    }
}

void consolePrintChar(char c) @nogc nothrow
{
    if (c == 0)
        return;
    else if (c == '\n')
    {
        console.print_x = 0;
        console.print_y += console.v_stride;
        console.height += console.v_stride;
        return;
    }
    
    uint charX = CHAR_WIDTH * (c % 16);
    uint charY = CHAR_HEIGHT * (c / 16);
    uint baseX = console.x + console.print_x;
    uint baseY = console.y + console.print_y;
    for (uint y = 0; y < CHAR_HEIGHT; y++)
    {
        if (baseY + y >= console.fb.height)
            break;
        
        for (uint x = 0; x < CHAR_WIDTH; x++)
        {
            if (baseX + x >= console.fb.width)
                break;
            
            uint offset = (baseY + y) * (console.fb.pitch / console.fb.bytesPerPixel) + (baseX + x);
            uint pix = FONT[(charY + y) * FONT_ATLAS_WIDTH + (charX + x)];
            if (pix != 0x00FF00FF)
                console.fb.ptr[offset] = pix;
        }
    }
    
    console.print_x += console.h_stride;
    if (console.print_x >= console.width)
    {
        console.print_x = 0;
        console.print_y += console.v_stride;
        console.height += console.v_stride;
    }
}

void consolePrintString(string str) @nogc nothrow
{
    for (size_t i = 0; i < str.length; i++)
    {
        consolePrintChar(str[i]);
    }
}

void consoleBack() @nogc nothrow
{
    if (console.print_x > 0)
    {
        console.print_x -= console.h_stride;
        
        uint baseX = console.x + console.print_x;
        uint baseY = console.y + console.print_y;
        
        for (uint y = 0; y < CHAR_HEIGHT; y++)
        {
            if (baseY + y >= console.fb.height)
                break;
            
            for (uint x = 0; x < CHAR_WIDTH; x++)
            {
                if (baseX + x >= console.fb.width)
                    break;
                
                uint offset = (baseY + y) * (console.fb.pitch / console.fb.bytesPerPixel) + (baseX + x);
                console.fb.ptr[offset] = console.clear_color;
            }
        }
    }
}

void consoleNewline() @nogc nothrow
{
    console.print_x = 0;
    console.print_y += console.v_stride;
    console.height += console.v_stride;
}

immutable char[16] HEXMAP = [
    '0', '1', '2', '3', 
    '4', '5', '6', '7', 
    '8', '9', 'A', 'B', 
    'C', 'D', 'E', 'F'
];

void consolePrintStringFmt(string fmt, va_list ap) @nogc nothrow
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
                    consolePrintChar(n);
                }
            }
            else if (fmt[i] == 'c')
            {
                consolePrintChar(va_arg!(char)(ap));
            }
            else if (fmt[i] == 'x')
            {
                uint u = va_arg!(uint)(ap);
                consolePrintString("0x");
                char[8] digits;
                for (int j = 7; j >= 0; j--)
                {
                    digits[j] = HEXMAP[u & 0x0F];
                    u >>= 4;
                }
                foreach(char d; digits)
                    consolePrintChar(d);
            }
            else if (fmt[i] == 'k')
            {
                ushort u = va_arg!(ushort)(ap);
                consolePrintString("0x");
                char[4] digits;
                for (int j = 3; j >= 0; j--)
                {
                    digits[j] = HEXMAP[u & 0x0F];
                    u >>= 4;
                }
                foreach(char d; digits)
                    consolePrintChar(d);
            }
            else if (fmt[i] == 'd')
            {
                int w = va_arg!(int)(ap);
                if (w < 0)
                {
                    f = -w;
                    consolePrintChar('-');
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
                        consolePrintChar(d[k]);
                    }
                }
            }
            else if (fmt[i] == 'X')
            {
                ubyte b = va_arg!(ubyte)(ap);
                consolePrintString("0x");
                consolePrintChar(HEXMAP[(b & 0xF0) >> 4]);
                consolePrintChar(HEXMAP[b & 0x0F]);
            }
            else
            {
                consolePrintChar(fmt[i]);
            }
        }
        else
        {
            consolePrintChar(c);
        }
    }
}

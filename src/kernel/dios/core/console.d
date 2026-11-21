module dios.core.console;

import dios.core.vga;
import dios.core.framebuffer;
import dios.core.font;
import dios.core.mem;
import dios.core.gfx;

import core.stdc.stdarg;

struct ConsoleState
{
    Framebuffer* fb;
    uint x;
    uint y;
    uint width;
    uint height;     // visible height of the text area in pixels (a whole number of lines)
    uint print_x;
    uint print_y;
    uint h_stride;
    uint v_stride;
    uint clear_color;
    bool cursorOn;   // the blinking text cursor is currently XOR-ed into the scene
}

__gshared ConsoleState console;

enum uint CONSOLE_MAX_ROWS = 512;
// rowWrapped[r] != 0: row r ended because the text ran into the right edge and
// continues on row r+1 (as opposed to an explicit newline). Lets backspace and
// cursor-left cross a soft wrap.
__gshared ubyte[CONSOLE_MAX_ROWS] rowWrapped;

extern(C):

ConsoleState* consoleInit(Framebuffer* fb, uint x, uint y) @nogc nothrow
{
    console.fb = fb;
    console.x = x;
    console.y = y;
    console.width = fb.width - x - 16;
    console.print_x = 0;
    console.print_y = 0;
    console.clear_color = 0x000000AA;
    console.h_stride = CHAR_WIDTH - 2;
    console.v_stride = CHAR_HEIGHT;
    console.cursorOn = false;
    for (uint r = 0; r < CONSOLE_MAX_ROWS; r++)
        rowWrapped[r] = 0;

    // The text area runs from y to the bottom of the screen, in whole lines.
    // Always keep at least one line so the scroll arithmetic stays sane.
    uint rows = (fb.height > y) ? (fb.height - y) / console.v_stride : 0;
    if (rows == 0)
        rows = 1;
    console.height = rows * console.v_stride;

    // (no full-screen clear any more: the console draws into the scene, which main()
    // has already filled with the background and the logo)
    return &console;
}

// XOR the cursor bar (the bottom of the current cell) into the scene.
// Doing it twice restores the pixels exactly.
void consoleCursorXor() @nogc nothrow
{
    gfxXorRect(cast(int)(console.x + console.print_x + 2),
               cast(int)(console.y + console.print_y + console.v_stride - 6),
               cast(int)console.h_stride, 3, 0x00FFFFFF);
}

// Blink phase flip; call this from the main loop on a timer.
void consoleCursorToggle() @nogc nothrow
{
    consoleCursorXor();
    console.cursorOn = !console.cursorOn;
}

// Scroll the text area up by one line and clear the line that frees up at the bottom.
void consoleScroll() @nogc nothrow
{
    Framebuffer* fb = console.fb;
    uint lines = console.v_stride;
    if (console.y >= fb.height || console.height <= lines)
    {
        // A single-line console: nothing to move, just blank it.
        lines = console.height;
    }
    else
    {
        // Rows are contiguous in the scene buffer, so the whole block is one move.
        uint* dst = fb.ptr + cast(size_t)console.y * (fb.pitch / fb.bytesPerPixel);
        const(uint)* src = dst + cast(size_t)lines * (fb.pitch / fb.bytesPerPixel);
        memmove(dst, src, cast(size_t)(console.height - lines) * fb.pitch);
    }

    // Blank the bottom line(s) across the full row width.
    uint stride = fb.pitch / fb.bytesPerPixel;
    uint first = console.y + console.height - lines;
    for (uint yy = first; yy < console.y + console.height && yy < fb.height; yy++)
    {
        uint* row = fb.ptr + cast(size_t)yy * stride;
        for (uint xx = 0; xx < fb.width; xx++)
            row[xx] = console.clear_color;
    }

    // Row flags follow the text up by one row.
    uint rows = console.height / console.v_stride;
    if (rows > CONSOLE_MAX_ROWS)
        rows = CONSOLE_MAX_ROWS;
    for (uint r = 0; r + 1 < rows; r++)
        rowWrapped[r] = rowWrapped[r + 1];
    if (rows != 0)
        rowWrapped[rows - 1] = 0;

    gfxDirty(0, cast(int)console.y, cast(int)fb.width, cast(int)console.height);
}

uint consoleRow() @nogc nothrow
{
    uint r = console.print_y / console.v_stride;
    return (r < CONSOLE_MAX_ROWS) ? r : CONSOLE_MAX_ROWS - 1;
}

// Number of character cells that fit in one row.
uint consoleCells() @nogc nothrow
{
    return (console.width + console.h_stride - 1) / console.h_stride;
}

// Move to the start of the next line, scrolling if that would run off the bottom.
// `wrapped` marks the row we leave as continuing on the next one (soft wrap).
void consoleLineFeedEx(bool wrapped) @nogc nothrow
{
    rowWrapped[consoleRow()] = wrapped ? 1 : 0;
    console.print_x = 0;
    console.print_y += console.v_stride;
    if (console.print_y + console.v_stride > console.height)
    {
        consoleScroll();
        console.print_y = console.height - console.v_stride;
    }
}

void consoleLineFeed() @nogc nothrow
{
    consoleLineFeedEx(false);
}

// Draw one character at the cursor position and advance. Does not touch the
// blinking cursor: use consolePrintChar from outside.
void consolePutChar(char c) @nogc nothrow
{
    if (c == 0)
        return;
    else if (c == '\r')
    {
        console.print_x = 0;
        return;
    }
    else if (c == '\n')
    {
        consoleLineFeed();
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
    
    gfxDirty(cast(int)baseX, cast(int)baseY, CHAR_WIDTH, CHAR_HEIGHT);

    console.print_x += console.h_stride;
    if (console.print_x >= console.width)
        consoleLineFeedEx(true);
}

void consolePrintChar(char c) @nogc nothrow
{
    // Take the blinking cursor out first (a scroll or a glyph would otherwise
    // smear it), and put it back at the new position afterwards.
    bool hadCursor = console.cursorOn;
    if (hadCursor)
        consoleCursorXor();
    consolePutChar(c);
    if (hadCursor)
        consoleCursorXor();
}

void consolePrintString(string str) @nogc nothrow
{
    for (size_t i = 0; i < str.length; i++)
    {
        consolePrintChar(str[i]);
    }
}

// Blank one character cell (no cursor handling, no movement).
void consoleClearCell(uint px, uint py) @nogc nothrow
{
    uint baseX = console.x + px;
    uint baseY = console.y + py;
    uint stride = console.fb.pitch / console.fb.bytesPerPixel;
    for (uint y = 0; y < CHAR_HEIGHT; y++)
    {
        if (baseY + y >= console.fb.height)
            break;
        for (uint x = 0; x < CHAR_WIDTH; x++)
        {
            if (baseX + x >= console.fb.width)
                break;
            console.fb.ptr[(baseY + y) * stride + (baseX + x)] = console.clear_color;
        }
    }
    gfxDirty(cast(int)baseX, cast(int)baseY, CHAR_WIDTH, CHAR_HEIGHT);
}

// Step the print position one cell left, crossing a soft wrap to the end of the
// previous row. Returns false at the start of a line (nothing to step over).
// No cursor handling.
bool consoleStepLeft() @nogc nothrow
{
    if (console.print_x >= console.h_stride)
    {
        console.print_x -= console.h_stride;
        return true;
    }
    uint row = consoleRow();
    if (row == 0 || console.print_y < console.v_stride || rowWrapped[row - 1] == 0)
        return false;
    rowWrapped[row - 1] = 0;
    console.print_y -= console.v_stride;
    console.print_x = (consoleCells() - 1) * console.h_stride;
    return true;
}

// Move the cursor one cell left without erasing. False at the line start.
bool consoleMoveLeft() @nogc nothrow
{
    bool hadCursor = console.cursorOn;
    if (hadCursor)
        consoleCursorXor();
    bool ok = consoleStepLeft();
    if (ok)
    {
        // The step un-wrapped the row above; moving left leaves the text where it is,
        // so keep the soft-wrap mark if we crossed one.
        uint row = consoleRow();
        if (console.print_x == (consoleCells() - 1) * console.h_stride && row + 1 < CONSOLE_MAX_ROWS)
            rowWrapped[row] = 1;
    }
    if (hadCursor)
        consoleCursorXor();
    return ok;
}

// Move the cursor one cell right (wrapping to the next row, scrolling if needed).
void consoleMoveRight() @nogc nothrow
{
    bool hadCursor = console.cursorOn;
    if (hadCursor)
        consoleCursorXor();
    console.print_x += console.h_stride;
    if (console.print_x >= console.width)
        consoleLineFeedEx(true);
    if (hadCursor)
        consoleCursorXor();
}

// Blank the cell under the cursor (used to trim the tail after an edit).
void consoleEraseHere() @nogc nothrow
{
    bool hadCursor = console.cursorOn;
    if (hadCursor)
        consoleCursorXor();
    consoleClearCell(console.print_x, console.print_y);
    if (hadCursor)
        consoleCursorXor();
}

// Step back one cell and erase it; crosses soft-wrapped line breaks.
void consoleBack() @nogc nothrow
{
    bool hadCursor = console.cursorOn;
    if (hadCursor)
        consoleCursorXor();
    if (consoleStepLeft())
        consoleClearCell(console.print_x, console.print_y);
    if (hadCursor)
        consoleCursorXor();
}

// Blank the whole text area and home the cursor.
void consoleClear() @nogc nothrow
{
    bool hadCursor = console.cursorOn;
    if (hadCursor)
        consoleCursorXor();

    Framebuffer* fb = console.fb;
    uint stride = fb.pitch / fb.bytesPerPixel;
    for (uint yy = console.y; yy < console.y + console.height && yy < fb.height; yy++)
    {
        uint* row = fb.ptr + cast(size_t)yy * stride;
        for (uint xx = 0; xx < fb.width; xx++)
            row[xx] = console.clear_color;
    }
    gfxDirty(0, cast(int)console.y, cast(int)fb.width, cast(int)console.height);

    for (uint r = 0; r < CONSOLE_MAX_ROWS; r++)
        rowWrapped[r] = 0;
    console.print_x = 0;
    console.print_y = 0;

    if (hadCursor)
        consoleCursorXor();
}

void consoleNewline() @nogc nothrow
{
    bool hadCursor = console.cursorOn;
    if (hadCursor)
        consoleCursorXor();
    consoleLineFeed();
    if (hadCursor)
        consoleCursorXor();
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
            
            // %llx
            if (fmt[i] == 'l' && i + 1 < fmt.length && fmt[i + 1] == 'l')
            {
                i++;
                if (++i >= fmt.length)
                    break;

                if (fmt[i] == 'x')
                {
                    ulong u = va_arg!(ulong)(ap);
                    consolePrintString("0x");
                    char[16] digits;
                    for (int j = 15; j >= 0; j--)
                    {
                        digits[j] = HEXMAP[u & 0x0F];
                        u >>= 4;
                    }
                    foreach (char d; digits)
                        consolePrintChar(d);
                    continue;
                }
                else if (fmt[i] == 'u')
                {
                    ulong u = va_arg!(ulong)(ap);
                    char[20] d;
                    int k = 19;
                    do
                    {
                        d[k] = cast(char)((u % 10) + '0');
                        u /= 10;
                        k--;
                    }
                    while (u && k >= 0);
                    while (++k < 20)
                        consolePrintChar(d[k]);
                    continue;
                }
            }
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

// VGA text mode fallback
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

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

/**
 * GTerm - a terminal window.
 *
 * How it works: GTerm asks the kernel for an output channel (chCreate) and starts programs
 * with uspawn(), telling the kernel to send their uwrite()/uprintf() output to that channel
 * instead of the kernel console. It reads the channel (chRead) and draws the characters
 * into an 80x25 grid.
 *
 * Bytes GTerm understands: printable ASCII, '\n', '\r', 8 (backspace), 9 (tab), 12 (clear).
 *
 * Usage: type a program name with arguments and press Enter.
 * Programs are looked up as /bin/<name>.elf, /bin/<name>; a name with a '/' is used as given
 * (".elf" is tried too). Built-in commands: help, cd, clear, exit.
 *
 * A command ending with '&' runs in the background: the prompt comes back at once, and the
 * program's output appears above the line being typed. "[ID] done" is shown when it ends.
 * Without '&' the prompt waits for the program.
 *
 * Not yet implemented:
 *  - input for the programs (they cannot read keys),
 *  - a way to stop a running program
 *  - scrollback.
 */

import ulib.dios;
import ulib.gfx;

enum uint COLS = 80;
enum uint ROWS = 25;
enum int CELL_W = 7; // distance between two characters
enum int CELL_H = 14;
enum int GLYPH_W = 8; // size of a glyph in the font picture (wider than CELL_W: they overlap)
enum int GLYPH_H = 14;
enum int ATLAS_COLS = 16; // glyph c is at column c % 16, row c / 16
enum int MARGIN = 6; // empty border around the text, in pixels
enum uint WIN_W = COLS * CELL_W + (GLYPH_W - CELL_W) + 2 * MARGIN;
enum uint WIN_H = ROWS * CELL_H + 2 * MARGIN;

enum uint COLOR_BG     = 0x003a004d; //0x00101820;
enum uint COLOR_FG     = 0x00FFFFFF; //0x00C8D0D8;
enum uint COLOR_CURSOR = 0x00FFFFFF; //0x00C8D0D8;

enum uint LINE_MAX = 200; // longest command line (the kernel allows 255 bytes of arguments)
enum uint NAME_MAX = 64;
enum uint PATH_MAX = 128;

enum uint MAX_BG = 8; // background programs that are watched (more can run, but without the "done" message)

enum uint MAX_READS_PER_FRAME = 16; // 16 x 256 bytes: a chatty program must not freeze the window
enum ulong BLINK_MS = 500;

__gshared Window win;
__gshared ImageBGRA fontImage;
__gshared Canvas font;
__gshared int tty = -1;

__gshared char[COLS * ROWS] cells;
__gshared uint curX;
__gshared uint curY;

__gshared char[LINE_MAX] line;
__gshared uint lineLen;

__gshared bool running = true;
__gshared bool busy; // a program is running: no command line until it has ended
__gshared uint fgTask; // task id of the program the prompt waits for (when busy)
__gshared uint[MAX_BG] bgTasks; // task ids of the background programs, 0 = free slot
__gshared uint promptY; // row where the command line starts
__gshared bool parked; // the command line is taken off the screen while output is printed
__gshared bool dirty = true;
__gshared ulong blinkPhase;

// Screen grid

void termClear() @nogc nothrow
{
    for (uint i = 0; i < COLS * ROWS; i++)
        cells[i] = ' ';
    curX = 0;
    curY = 0;
    promptY = 0;
    dirty = true;
}

void termScroll() @nogc nothrow
{
    memmove(cells.ptr, cells.ptr + COLS, COLS * (ROWS - 1));
    if (promptY > 0)
        promptY--;
    for (uint i = 0; i < COLS; i++)
        cells[COLS * (ROWS - 1) + i] = ' ';
}

void termNewline() @nogc nothrow
{
    curX = 0;
    curY++;
    if (curY >= ROWS)
    {
        termScroll();
        curY = ROWS - 1;
    }
}

/// One byte of output.
void termPutChar(ubyte c) @nogc nothrow
{
    dirty = true;
    if (c == '\n')
        termNewline();
    else if (c == '\r')
        curX = 0;
    else if (c == 8)
    {
        // back one cell (over a wrapped line break too) and erase it
        if (curX > 0)
            curX--;
        else if (curY > 0)
        {
            curY--;
            curX = COLS - 1;
        }
        cells[curY * COLS + curX] = ' ';
    }
    else if (c == 9)
    {
        for (uint i = 0; i < 4; i++)
            termPutChar(' ');
    }
    else if (c == 12)
        termClear();
    else
    {
        cells[curY * COLS + curX] = (c >= 32 && c < 127) ? cast(char)c : '?';
        curX++;
        if (curX >= COLS)
            termNewline();
    }
}

void termPutString(const(char)* s) @nogc nothrow
{
    while (*s != 0)
        termPutChar(cast(ubyte)*s++);
}

void termPutUint(uint v) @nogc nothrow
{
    char[10] d;
    uint k = d.length;
    do
    {
        d[--k] = cast(char)('0' + v % 10);
        v /= 10;
    }
    while (v != 0);
    for (; k < d.length; k++)
        termPutChar(cast(ubyte)d[k]);
}

void showPrompt() @nogc nothrow
{
    if (curX != 0)
        termNewline();                  // the program's last line had no newline
    promptY = curY;
    termPutString("> ");
}

void prompt() @nogc nothrow
{
    lineLen = 0;
    showPrompt();
}

// Output of a background program arrives while the user may be typing: take the prompt and the
// line off the screen first (parkInput), and put them back below the output (unparkInput).

void parkInput() @nogc nothrow
{
    if (busy || parked)
        return;
    for (uint i = promptY * COLS; i < (curY + 1) * COLS; i++)
        cells[i] = ' ';
    curX = 0;
    curY = promptY;
    parked = true;
    dirty = true;
}

void unparkInput() @nogc nothrow
{
    if (!parked)
        return;
    parked = false;
    showPrompt();
    for (uint i = 0; i < lineLen; i++)
        termPutChar(cast(ubyte)line[i]);
}

/// "[id] text" at the cursor, which must be at the start of a line.
void printJob(uint id, const(char)* text) @nogc nothrow
{
    termPutChar('[');
    termPutUint(id);
    termPutString("] ");
    termPutString(text);
    termPutChar('\n');
}

/// The same for a message that comes at any time (a background program has ended): on a line of
/// its own, without disturbing the command line.
void notifyJob(uint id, const(char)* text) @nogc nothrow
{
    parkInput();
    if (busy && curX != 0)
        termNewline();
    printJob(id, text);
}

// Drawing

void drawGlyph(char c, int px, int py) @nogc nothrow
{
    immutable int gx = (cast(int)c % ATLAS_COLS) * GLYPH_W;
    immutable int gy = (cast(int)c / ATLAS_COLS) * GLYPH_H;

    for (int y = 0; y < GLYPH_H; y++)
    {
        for (int x = 0; x < GLYPH_W; x++)
        {
            immutable uint a = font.getPixel(gx + x, gy + y) >>> 24;  // coverage
            if (a == 0)                      // fully transparent: leave background
                continue;
            if (a == 255)                    // fully opaque: no read needed
            {
                win.canvas.setPixel(px + x, py + y, COLOR_FG);
                continue;
            }
            immutable uint dst = win.canvas.getPixel(px + x, py + y);
            win.canvas.setPixel(px + x, py + y, blend(COLOR_FG, dst, a));
        }
    }
}

// result = fg * a/255 + bg * (255-a)/255, per channel
uint blend(uint fg, uint bg, uint a) @nogc nothrow pure
{
    immutable uint ia = 255 - a;
    uint result = 0;
    foreach (shift; [16, 8, 0])              // R, G, B (order doesn't matter)
    {
        immutable uint f = (fg >> shift) & 0xFF;
        immutable uint b = (bg >> shift) & 0xFF;
        result |= (((f * a + b * ia + 127) / 255) & 0xFF) << shift;
    }
    return result;                           // alpha byte left as 0
}

void render() @nogc nothrow
{
    win.canvas.clear(COLOR_BG);
    for (uint row = 0; row < ROWS; row++)
    {
        for (uint col = 0; col < COLS; col++)
        {
            char c = cells[row * COLS + col];
            if (c != ' ')
                drawGlyph(c,
                          MARGIN + cast(int)(col * CELL_W),
                          MARGIN + cast(int)(row * CELL_H));
        }
    }
    if (!busy && (blinkPhase & 1) == 0)
        win.canvas.fillRect(MARGIN + cast(int)(curX * CELL_W),
                            MARGIN + cast(int)(curY * CELL_H + CELL_H - 3),
                            CELL_W, 2, COLOR_CURSOR);
    windowCommit(&win);
}

// Channel

/// Moves what the programs wrote into the grid. True when the channel is empty afterwards.
bool pump() @nogc nothrow
{
    ubyte[256] buf;
    for (uint i = 0; i < MAX_READS_PER_FRAME; i++)
    {
        long n = chRead(tty, buf.ptr, buf.length);
        if (n <= 0)
            return true;
        parkInput();
        for (long k = 0; k < n; k++)
            termPutChar(buf[cast(size_t)k]);
    }
    return false;
}

// Command line

bool isSpace(char c) @nogc nothrow
{
    return c == ' ' || c == '\t';
}

bool streq(const(char)* a, const(char)* b) @nogc nothrow
{
    while (*a != 0 && *a == *b)
    {
        a++;
        b++;
    }
    return *a == *b;
}

/// Appends the C string `s` to dst at position n (dst has room for cap bytes). New n, or cap if it did not fit.
uint appendStr(char* dst, uint cap, uint n, const(char)* s) @nogc nothrow
{
    while (*s != 0)
    {
        if (n + 1 >= cap)
            return cap;
        dst[n++] = *s++;
    }
    return n;
}

/// dst = a ~ b ~ c, as a C string. False if it does not fit.
bool joinPath(char* dst, uint cap, const(char)* a, const(char)* b, const(char)* c) @nogc nothrow
{
    uint n = appendStr(dst, cap, 0, a);
    n = appendStr(dst, cap, n, b);
    n = appendStr(dst, cap, n, c);
    if (n >= cap)
        return false;
    dst[n] = 0;
    return true;
}

bool isFile(const(char)* path) @nogc nothrow
{
    UStat st;
    return ustat(path, &st) == 0 && st.isDir == 0;
}

/// Finds the program file for a typed name. False if there is none.
bool resolve(const(char)* name, char* path) @nogc nothrow
{
    bool hasSlash = false;
    for (const(char)* p = name; *p != 0; p++)
        if (*p == '/')
            hasSlash = true;

    if (hasSlash)
        return (joinPath(path, PATH_MAX, name, "", "") && isFile(path)) ||
               (joinPath(path, PATH_MAX, name, ".elf", "") && isFile(path));
    return (joinPath(path, PATH_MAX, "/bin/", name, ".elf") && isFile(path)) ||
           (joinPath(path, PATH_MAX, "/bin/", name, "") && isFile(path));
}

void runLine() @nogc nothrow
{
    termNewline();

    // A trailing '&' means: do not wait for the program
    bool background = false;
    while (lineLen > 0 && isSpace(line[lineLen - 1]))
        lineLen--;
    if (lineLen > 0 && line[lineLen - 1] == '&')
    {
        background = true;
        lineLen--;
        while (lineLen > 0 && isSpace(line[lineLen - 1]))
            lineLen--;
    }
    line[lineLen] = 0;

    // First word: the program, the rest: its arguments
    char[NAME_MAX] name;
    uint i = 0;
    while (i < lineLen && isSpace(line[i]))
        i++;
    uint n = 0;
    while (i < lineLen && !isSpace(line[i]))
    {
        if (n + 1 < NAME_MAX)
            name[n++] = line[i];
        i++;
    }
    name[n] = 0;
    while (i < lineLen && isSpace(line[i]))
        i++;
    const(char)* args = line.ptr + i; // ends at line[lineLen] == 0

    if (n == 0)
    {
        prompt();
    }
    else if (streq(name.ptr, "exit"))
    {
        running = false;
    }
    else if (streq(name.ptr, "clear"))
    {
        termClear();
        prompt();
    }
    else if (streq(name.ptr, "cd"))
    {
        // Built in: the current directory belongs to this program, and programs started from
        // here begin in it. A separate `cd` program could only change its own.
        int r = uchdir(args[0] == 0 ? "/" : args);
        if (r != 0)
        {
            termPutString("cd: ");
            termPutString(args);
            termPutString(r == UERR_NOT_DIR ? ": not a directory\n" : ": no such directory\n");
        }
        prompt();
    }
    else if (streq(name.ptr, "help"))
    {
        termPutString("Type a program name and its arguments, then Enter.\n");
        termPutString("Programs are searched in /bin. Built-ins: help, cd, clear, exit.\n");
        termPutString("End a command with & to run it in the background.\n");
        prompt();
    }
    else
    {
        char[PATH_MAX] path;
        if (!resolve(name.ptr, path.ptr))
        {
            termPutString("No such program: ");
            termPutString(name.ptr);
            termPutChar('\n');
            prompt();
        }
        else
        {
            int id = uspawn(path.ptr, args, cast(uint)tty);
            if (id < 0)
            {
                termPutString("Could not start ");
                termPutString(path.ptr);
                termPutChar('\n');
                prompt();
            }
            else if (background)
            {
                for (uint k = 0; k < MAX_BG; k++)
                {
                    if (bgTasks[k] == 0)
                    {
                        bgTasks[k] = cast(uint)id;
                        break;
                    }
                }
                printJob(cast(uint)id, name.ptr); // the cursor is on a fresh line below the command
                prompt();
            }
            else
            {
                fgTask = cast(uint)id;
                busy = true; // service() brings the prompt back when it has ended
            }
        }
    }
}

// Events

void handleKey(const(GfxEvent)* ev) @nogc nothrow
{
    if (busy || (ev.c & (GFX_MOD_CTRL | GFX_MOD_EXT)) != 0)
        return;
    int c = ev.b;
    if (c == 10 || c == 13)
        runLine();
    else if (c == 8)
    {
        if (lineLen > 0)
        {
            lineLen--;
            termPutChar(8);
        }
    }
    else if (c >= 32 && c < 127 && lineLen + 1 < LINE_MAX)
    {
        line[lineLen++] = cast(char)c;
        termPutChar(cast(ubyte)c);
    }
}

void handleEvent(const(GfxEvent)* ev) @nogc nothrow
{
    if (ev.type == GFX_EV_KEY)
        handleKey(ev);
    else if (ev.type == GFX_EV_CLOSE)
        running = false;
}

/// Once a frame: bring in the output; when the program has ended and everything it wrote is shown, new prompt.
void service() @nogc nothrow
{
    // Asked before the output is read: a program that has ended cannot write any more, so once
    // the channel is empty after this, all of its output has been shown.
    bool fgGone = busy && !utaskalive(cast(int)fgTask);
    bool[MAX_BG] bgGone;
    for (uint k = 0; k < MAX_BG; k++)
        bgGone[k] = bgTasks[k] != 0 && !utaskalive(cast(int)bgTasks[k]);

    bool drained = pump();
    if (drained)
    {
        for (uint k = 0; k < MAX_BG; k++)
        {
            if (bgGone[k])
            {
                notifyJob(bgTasks[k], "done");
                bgTasks[k] = 0;
            }
        }
        if (fgGone)
        {
            busy = false;
            fgTask = 0;
            prompt();
        }
    }
    unparkInput();
    ulong phase = uticks() / BLINK_MS;
    if (phase != blinkPhase)
    {
        blinkPhase = phase;
        dirty = true;
    }
}

// Start

bool loadFont(const(char)* path) @nogc nothrow
{
    UStat st;
    if (ustat(path, &st) != 0 || st.size < TGAHeader.sizeof)
        return false;
    size_t len = cast(size_t)st.size;
    int f = uopen(path, O_RDONLY);
    if (f < 0)
        return false;
    ubyte* buf = cast(ubyte*)umalloc(len);
    if (buf is null)
    {
        uclose(f);
        return false;
    }
    bool ok = ureadfull(f, buf, len) == cast(long)len;
    uclose(f);
    ok = ok && loadTGA(buf[0 .. len], &fontImage);
    ufree(buf);
    if (!ok)
        return false;
    imageAsCanvas(&fontImage, &font);
    // glyphs are read from (c % 16) * 10, (c / 16) * 12: the picture must be that big for c < 128
    return font.width >= ATLAS_COLS * GLYPH_W && font.height >= 8 * GLYPH_H;
}

int main(string[] args)
{
    if (!loadFont("/etc/gterm/font.tga"))
    {
        uputs("gterm: cannot load /etc/gterm/font.tga\n");
        return 1;
    }
    if (!windowCreate(&win, WIN_W, WIN_H))
    {
        uputs("gterm: could not create a window\n");
        return 1;
    }
    if (!win.serverRunning)
        uputs("gterm: no graphics server running yet (gfx start); the window shows up when it is\n");

    tty = chCreate();
    if (tty < 0)
    {
        uputs("gterm: no output channel available\n");
        windowClose(&win);
        return 1;
    }

    termClear();
    termPutString("DIOS Terminal\n");
    termPutString("Enter 'help' to list the built-in commands.\n");
    prompt();

    while (running)
    {
        GfxEvent ev;
        bool got = windowPoll(&win, &ev, 16);
        while (got)
        {
            handleEvent(&ev);
            got = windowPoll(&win, &ev, 0);
        }
        service();
        if (dirty)
        {
            render();
            dirty = false;
        }
    }

    chClose(tty); // programs still running lose their output
    windowClose(&win);
    if (fontImage.data.length > 0)
        ufree(fontImage.data.ptr);
    return 0;
}

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

module ulib.gfx.window;

/**
 * The application side of the graphics server.
 *
 *     Window win;
 *     if (!windowCreate(&win, 320, 240)) ...        // a drawable area
 *     win.canvas.fillRect(10, 10, 50, 50, rgb(255, 0, 0));
 *     windowCommit(&win);                           // "I changed something, show it"
 *     GfxEvent ev;
 *     while (windowPoll(&win, &ev, 16)) ...         // input and friends, up to 16 ms wait
 *     windowClose(&win);
 *
 * Without a graphics server (or while the shell has the screen) all of this still works,
 * but nothing is displayed. The memory of the window is freed when the program ends.
 */

import ulib.gfx.proto;
import ulib.gfx.canvas;

struct Window
{
    uint id;                // kernel surface id, 0 = not open
    Canvas canvas;          // draw here
    bool serverRunning;     // is a graphics server running? (kept up to date by windowPoll)
    uint flags;             // GFX_WIN_* requested from the window manager (see windowSetHints)
    int posX, posY;         // ... and the position that goes with GFX_WIN_POSITION
}

extern(C):

// Sends the window's flags and position to the server. Silently does nothing without one.
private void windowSendHints(Window* win) @nogc nothrow
{
    if (win.id == 0)
        return;
    GfxEvent e;
    e.type = GFX_EV_WM_HINTS;
    e.a = cast(int)win.flags;
    e.b = win.posX;
    e.c = win.posY;
    ugfxSend(win.id, &e);
}

/**
 * Opens a window of width x height pixels (black). False if it could not be created
 * (too big, too many windows, out of memory).
 */
bool windowCreate(Window* win, uint width, uint height) @nogc nothrow
{
    GfxSurfaceDesc d;
    d.id = 0;
    d.width = width;
    d.height = height;
    d.stride = 0;
    d.pixels = null;
    d.owner = 0;
    d.reserved = 0;
    if (ugfxSurfaceCreate(&d) != 0)
        return false;

    win.id = d.id;
    win.canvas.pixels = d.pixels;
    win.canvas.width = cast(int)d.width;
    win.canvas.height = cast(int)d.height;
    win.canvas.stride = cast(int)(d.stride / 4);
    win.flags = 0;
    win.posX = 0;
    win.posY = 0;

    GfxInfo info;
    win.serverRunning = ugfxInfo(&info) == 0 && (info.flags & GFX_INFO_SERVER) != 0;
    return true;
}

/**
 * Asks the window manager to treat the window in a special way: `flags` is a combination of
 * GFX_WIN_* (0 = an ordinary window again). With GFX_WIN_POSITION the window is put at x, y
 * on the screen (its top left drawable pixel); without it x and y are ignored and the window
 * stays where it is.
 *
 * It is a request that takes effect when the server handles it. It is repeated by windowPoll()
 * whenever a server starts, so keep polling events (as every window program does).
 */
void windowSetHints(Window* win, uint flags, int x, int y) @nogc nothrow
{
    win.flags = flags & GFX_WIN_ALL;
    win.posX = x;
    win.posY = y;
    windowSendHints(win);
}

/// Moves a window that has the GFX_WIN_POSITION hint (or gives it one) to x, y on the screen.
void windowSetPosition(Window* win, int x, int y) @nogc nothrow
{
    windowSetHints(win, win.flags | GFX_WIN_POSITION, x, y);
}

/**
 * Opens a window for a desktop shell (a background, a taskbar, a widget): no frame, cannot be
 * moved by the user, always below all other windows, at x, y on the screen. The size of the
 * screen is in ugfxInfo(). Example, a 32 pixel taskbar along the bottom edge:
 *
 *     GfxInfo info;
 *     ugfxInfo(&info);
 *     windowCreateDesktop(&bar, info.width, 32, 0, info.height - 32);
 *
 * Returns false if the window could not be created, like windowCreate().
 */
bool windowCreateDesktop(Window* win, uint width, uint height, int x, int y) @nogc nothrow
{
    if (!windowCreate(win, width, height))
        return false;
    windowSetHints(win, GFX_WIN_DESKTOP, x, y);
    return true;
}

/// Tells the server that all of the window changed.
void windowCommit(Window* win) @nogc nothrow
{
    ugfxSurfaceCommit(win.id, null);
}

/// Tells the server that only x, y, w, h changed (cheaper when it can do something with that).
void windowCommitRect(Window* win, int x, int y, int w, int h) @nogc nothrow
{
    GfxRect r;
    r.x = x;
    r.y = y;
    r.w = w;
    r.h = h;
    ugfxSurfaceCommit(win.id, &r);
}

/**
 * The next event for this program (see GFX_EV_*). Waits up to `timeoutMs`: 0 = do not wait,
 * negative = for as long as it takes. False if there was none.
 * Typical events for a window: GFX_EV_KEY, GFX_EV_MOUSE (coordinates relative to the
 * window), GFX_EV_FOCUS, GFX_EV_CLOSE; and GFX_EV_SERVER (a server started or stopped).
 */
bool windowPoll(Window* win, GfxEvent* ev, long timeoutMs) @nogc nothrow
{
    if (ugfxPoll(ev, timeoutMs) != 1)
        return false;
    if (ev.type == GFX_EV_SERVER)
    {
        win.serverRunning = ev.a != 0;
        // A server that starts knows nothing about us yet (hints sent before it were dropped)
        if (ev.a != 0 && win.flags != 0)
            windowSendHints(win);
    }
    return true;
}

/// Closes the window. The canvas must not be used afterwards.
void windowClose(Window* win) @nogc nothrow
{
    if (win.id != 0)
        ugfxSurfaceDestroy(win.id);
    win.id = 0;
    win.canvas.pixels = null;
    win.canvas.width = 0;
    win.canvas.height = 0;
    win.canvas.stride = 0;
}

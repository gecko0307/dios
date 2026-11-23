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
}

extern(C):

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

    GfxInfo info;
    win.serverRunning = ugfxInfo(&info) == 0 && (info.flags & GFX_INFO_SERVER) != 0;
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
        win.serverRunning = ev.a != 0;
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

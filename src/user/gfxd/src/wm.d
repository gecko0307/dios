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

module wm;

/**
 * Window logic of the graphics server: which windows exist, where they are, in which order
 * they overlap, who has the keyboard, and what a mouse click or a key press means.
 *
 * A "window" here is a kernel surface (the client's drawable area, mapped into this program)
 * plus a position. There is no decoration, no dragging, no resizing yet - this is the file to
 * grow all of that in. Ideas, roughly in order:
 *   - title bar + close button (draw in render.d; a click on it sends GFX_EV_CLOSE)
 *   - dragging windows (state next to wmGrab: a click on the title bar starts a drag)
 *   - a taskbar / launcher, desktop icons
 *   - per-window dirty rectangles (see GFX_EV_SURFACE_DAMAGE) instead of redrawing everything
 */

import ulib.dios;
import ulib.gfx;

enum int WM_MAX_WINDOWS = 32;

struct WmWindow
{
    bool used;
    uint surface;       // kernel surface id
    uint owner;         // task id of the program that owns it (see `ps` in the shell)
    int x, y;           // screen position of the top left corner of the drawable area
    Canvas canvas;      // the client's pixels, mapped into this program. Read only for us, by convention
}

// All state is __gshared: user programs have no thread local storage.
__gshared WmWindow[WM_MAX_WINDOWS] wmWindows;
__gshared int[WM_MAX_WINDOWS] wmOrder;      // indices into wmWindows, back to front
__gshared int wmCount;                      // how many entries of wmOrder are valid
__gshared int wmFocus = -1;                 // window that gets the keyboard, -1: none
__gshared int wmGrab = -1;                  // window that gets the mouse while a button is down
__gshared int wmCascade;                    // where the next window goes
__gshared int wmMouseX;
__gshared int wmMouseY;
__gshared uint wmButtons;

void wmInit()
{
    for (int i = 0; i < WM_MAX_WINDOWS; i++)
        wmWindows[i].used = false;
    wmCount = 0;
    wmFocus = -1;
    wmGrab = -1;
    wmCascade = 0;
}

/// Index of the window of a kernel surface, -1 if we do not have one.
int wmFind(uint surface)
{
    for (int i = 0; i < WM_MAX_WINDOWS; i++)
        if (wmWindows[i].used && wmWindows[i].surface == surface)
            return i;
    return -1;
}

private void wmSendFocus(int idx, int gained)
{
    GfxEvent e;
    e.type = GFX_EV_FOCUS;
    e.a = gained;
    ugfxSend(wmWindows[idx].surface, &e);
}

/// Gives the keyboard to window `idx` (-1: nobody). The windows are told.
void wmSetFocus(int idx)
{
    if (idx == wmFocus)
        return;
    if (wmFocus >= 0)
        wmSendFocus(wmFocus, 0);
    wmFocus = idx;
    if (idx >= 0)
        wmSendFocus(idx, 1);
}

/// Moves window `idx` in front of all others.
void wmRaise(int idx)
{
    int j = 0;
    for (int i = 0; i < wmCount; i++)
        if (wmOrder[i] != idx)
            wmOrder[j++] = wmOrder[i];
    wmOrder[j++] = idx;
    wmCount = j;
}

/// A program created a surface (GFX_EV_SURFACE_NEW): map it and give it a window.
/// Returns the window index, or -1 (too many windows, or the kernel refused to map it).
int wmAdd(uint surface, uint owner)
{
    int slot = -1;
    for (int i = 0; i < WM_MAX_WINDOWS; i++)
    {
        if (!wmWindows[i].used)
        {
            slot = i;
            break;
        }
    }
    if (slot < 0)
        return -1;

    GfxSurfaceDesc d;
    d.id = surface;
    if (ugfxServerMap(&d) != 0)
        return -1;

    WmWindow* w = &wmWindows[slot];
    w.used = true;
    w.surface = surface;
    w.owner = owner;
    w.canvas.pixels = d.pixels;
    w.canvas.width = cast(int)d.width;
    w.canvas.height = cast(int)d.height;
    w.canvas.stride = cast(int)(d.stride / 4);
    w.x = 40 + (wmCascade % 8) * 32;
    w.y = 40 + (wmCascade % 8) * 32;
    wmCascade++;

    wmOrder[wmCount++] = slot;
    wmSetFocus(slot); // new windows get the keyboard
    return slot;
}

/// The program that owned the surface is gone (GFX_EV_SURFACE_GONE).
void wmRemove(uint surface)
{
    int idx = wmFind(surface);
    if (idx >= 0)
    {
        // Forget the window BEFORE letting go of the memory: nothing may touch its pixels afterwards.
        wmWindows[idx].used = false;
        wmWindows[idx].canvas.pixels = null;

        int j = 0;
        for (int i = 0; i < wmCount; i++)
            if (wmOrder[i] != idx)
                wmOrder[j++] = wmOrder[i];
        wmCount = j;

        if (wmGrab == idx)
            wmGrab = -1;
        if (wmFocus == idx)
        {
            wmFocus = -1; // the window is gone, no FOCUS event for it
            wmSetFocus(wmCount > 0 ? wmOrder[wmCount - 1] : -1);
        }
    }
    // The kernel keeps the memory until we say we are done with it
    ugfxServerUnmap(surface);
}

/// The topmost window under a screen position, -1 if there is none.
int wmWindowAt(int x, int y)
{
    for (int i = wmCount - 1; i >= 0; i--)
    {
        int idx = wmOrder[i];
        WmWindow* w = &wmWindows[idx];
        if (x >= w.x && y >= w.y && x < w.x + w.canvas.width && y < w.y + w.canvas.height)
            return idx;
    }
    return -1;
}

/// A key press (GFX_EV_KEY). Goes to the window that has the keyboard.
void wmHandleKey(const(GfxEvent)* ev)
{
    if (wmFocus >= 0)
        ugfxSend(wmWindows[wmFocus].surface, ev);
}

/// The mouse moved or a button changed (GFX_EV_MOUSE, screen coordinates).
void wmHandleMouse(const(GfxEvent)* ev)
{
    wmMouseX = ev.a;
    wmMouseY = ev.b;
    uint buttons = cast(uint)ev.c;
    uint pressed = buttons & ~wmButtons;
    wmButtons = buttons;

    int hit = wmWindowAt(wmMouseX, wmMouseY);

    // A click brings the window to the front and gives it the keyboard. From then on, until
    // all buttons are up, the mouse belongs to that window (so dragging out of it works).
    if (pressed != 0 && wmGrab < 0)
    {
        if (hit >= 0)
        {
            wmRaise(hit);
            wmSetFocus(hit);
        }
        else
            wmSetFocus(-1);
        wmGrab = hit;
    }

    int target = (wmGrab >= 0) ? wmGrab : hit;
    if (target >= 0)
    {
        GfxEvent fwd = *ev;
        fwd.a = wmMouseX - wmWindows[target].x; // relative to the window's drawable area
        fwd.b = wmMouseY - wmWindows[target].y;
        ugfxSend(wmWindows[target].surface, &fwd);
    }

    if (buttons == 0)
        wmGrab = -1;
}

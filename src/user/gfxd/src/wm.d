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
 * A "window" is a kernel surface (the client's drawable area, mapped into this program) plus a
 * position, and a frame around it: a border and a title bar ABOVE the drawable area. (x, y) is
 * the top left of the drawable area, so clients never see the decoration.
 *
 *        +---------------------------+   <- outline (WM_OUTLINE wide, black), then the frame (WM_BORDER wide)
 *        | title bar            [ X ]|   <- WM_TITLE_H high; X = close button, WM_CLOSE_SIZE square
 *        +---------------------------+
 *        |                           |
 *        |   drawable area (x, y)    |
 *        +---------------------------+
 *
 * Windows can ask for special treatment with GFX_EV_WM_HINTS (flags GFX_WIN_*, see ulib.gfx.proto):
 *   BORDERLESS  no frame at all: the window is only its drawable area (frame == drawable area)
 *   FIXED       the title bar cannot be dragged
 *   BOTTOM      the window stays below all windows that do not have the flag (it is its own layer:
 *               raising it only brings it to the front of the BOTTOM windows; it does not
 *               grab the keyboard when it appears)
 *   TOP         the mirror image: always above everything else (popup menus, tooltips). Wins over BOTTOM
 *   POSITION    place the window at a given screen position
 * Together (GFX_WIN_DESKTOP) that is what a desktop background, a taskbar or a widget needs.
 *
 * Mouse: dragging the title bar moves the window; pressing and releasing the close button sends
 * the client GFX_EV_CLOSE (it decides what to do); a click anywhere raises the window and gives
 * it the keyboard. Everything on the drawable area is forwarded to the client.
 *
 * This module only decides; drawing is render.d. Changes to what is on screen are reported as
 * damage rectangles (wmTakeDamage), so that render.d redraws just those.
 *
 * Ideas to continue: resizing (a new surface + an event to the client), minimize, a taskbar,
 * keyboard shortcuts (Alt+Tab needs a modifier the kernel does not report yet).
 */

import ulib.dios;
import ulib.gfx;

enum int WM_MAX_WINDOWS = 32;
enum int WM_TITLE_H = 22;               // title bar height
enum int WM_CLOSE_SIZE = 20;            // the close button is a square this big, at the right end of the title bar
enum int WM_BORDER = 2;
enum int WM_OUTLINE = 1;                // black line around the whole frame of a decorated window

// Snapping: while a window is dragged by its title bar, its frame edges stick to the screen edges
// and to the edges of other windows' frames when they come this close (in pixels).
enum bool WM_SNAP_DEFAULT = true;       // the hardcoded switch. Later: read it from the config and set wmSnapEnabled
enum int WM_SNAP_DIST = 10;

// Which part of a window a point is on
enum int WM_PART_NONE   = 0;
enum int WM_PART_CLIENT = 1;            // the drawable area
enum int WM_PART_TITLE  = 2;            // title bar and border
enum int WM_PART_CLOSE  = 3;            // the close button

struct WmWindow
{
    bool used;
    uint surface;       // kernel surface id
    uint owner;         // task id of the program that owns it (see `ps` in the shell)
    int x, y;           // screen position of the top left corner of the drawable area
    uint flags;         // GFX_WIN_* (BORDERLESS, FIXED, BOTTOM, TOP), set by the client with GFX_EV_WM_HINTS
    Canvas canvas;      // the client's pixels, mapped into this program. Read only for us, by convention
}

// All state is __gshared: user programs have no thread local storage.
__gshared WmWindow[WM_MAX_WINDOWS] wmWindows;
__gshared int[WM_MAX_WINDOWS] wmOrder;      // indices into wmWindows, back to front
__gshared int wmCount;                      // how many entries of wmOrder are valid
__gshared int wmFocus = -1;                 // window that gets the keyboard, -1: none
__gshared int wmGrab = -1;                  // window a mouse button press started on, until all buttons are up
__gshared bool wmGrabClient;                // ... and it was on the drawable area (so the client gets the events)
__gshared int wmDrag = -1;                  // window being moved by its title bar
__gshared int wmDragDx;                     // mouse position inside the window when the drag started
__gshared int wmDragDy;
__gshared int wmCloseArmed = -1;            // window whose close button is pressed (fires on release)
__gshared int wmCascade;                    // where the next window goes
__gshared int wmMouseX;
__gshared int wmMouseY;
__gshared uint wmButtons;
__gshared int wmScreenW;
__gshared int wmScreenH;
__gshared bool wmSnapEnabled = WM_SNAP_DEFAULT;     // window snapping on/off; wmInit() resets it to WM_SNAP_DEFAULT

// Pending damage in screen coordinates (bounding box, half open); see wmTakeDamage()
__gshared bool wmHasDamage;
__gshared int wmDx0;
__gshared int wmDy0;
__gshared int wmDx1;
__gshared int wmDy1;

void wmInit(int screenW, int screenH)
{
    for (int i = 0; i < WM_MAX_WINDOWS; i++)
        wmWindows[i].used = false;
    wmCount = 0;
    wmFocus = -1;
    wmGrab = -1;
    wmDrag = -1;
    wmCloseArmed = -1;
    wmCascade = 0;
    wmScreenW = screenW;
    wmScreenH = screenH;
    wmSnapEnabled = WM_SNAP_DEFAULT;
    wmHasDamage = false;
}

// geometry

/// Does the window have a frame (border, title bar, close button)? Borderless ones do not.
bool wmDecorated(const(WmWindow)* w) { return (w.flags & GFX_WIN_BORDERLESS) == 0; }
bool wmIsBottom(const(WmWindow)* w) { return (w.flags & GFX_WIN_BOTTOM) != 0; }

/// The stacking layer of a set of flags: 0 = BOTTOM, 1 = ordinary, 2 = TOP. wmOrder is sorted by layer.
int wmLayerOfFlags(uint flags)
{
    if ((flags & GFX_WIN_TOP) != 0)
        return 2;
    if ((flags & GFX_WIN_BOTTOM) != 0)
        return 0;
    return 1;
}
int wmLayer(const(WmWindow)* w) { return wmLayerOfFlags(w.flags); }
bool wmIsFixed(const(WmWindow)* w) { return (w.flags & GFX_WIN_FIXED) != 0; }

// The frame: the area including decoration. Without decoration it is the drawable area.
// It includes the outline, which is the outermost line of it.
int wmFrameX(const(WmWindow)* w) { return wmDecorated(w) ? w.x - WM_BORDER - WM_OUTLINE : w.x; }
int wmFrameY(const(WmWindow)* w) { return wmDecorated(w) ? w.y - WM_TITLE_H - WM_BORDER - WM_OUTLINE : w.y; }
int wmFrameW(const(WmWindow)* w) { return wmDecorated(w) ? w.canvas.width + 2 * (WM_BORDER + WM_OUTLINE) : w.canvas.width; }
int wmFrameH(const(WmWindow)* w) { return wmDecorated(w) ? w.canvas.height + WM_TITLE_H + 2 * (WM_BORDER + WM_OUTLINE) : w.canvas.height; }

/// Left edge of the close button: it ends at the right edge of the drawable area, with the border to its right
int wmCloseX(const(WmWindow)* w) { return w.x + w.canvas.width - WM_CLOSE_SIZE; }

/// Top edge of the close button. It is placed so that the frame colour above it (the border and
/// whatever is left over in the title bar) is as thick as the one below it, between the button and the window.
int wmCloseY(const(WmWindow)* w) { return w.y - WM_TITLE_H + (WM_TITLE_H - WM_CLOSE_SIZE - WM_BORDER) / 2; }

/// The part of window `idx` at a screen position.
int wmHitPart(int idx, int px, int py)
{
    const(WmWindow)* w = &wmWindows[idx];
    if (px >= w.x && py >= w.y && px < w.x + w.canvas.width && py < w.y + w.canvas.height)
        return WM_PART_CLIENT;
    if (px < wmFrameX(w) || py < wmFrameY(w) || px >= wmFrameX(w) + wmFrameW(w) || py >= wmFrameY(w) + wmFrameH(w))
        return WM_PART_NONE;
    if (!wmDecorated(w))
        return WM_PART_NONE;                // the frame is the drawable area, which was tested above
    int cx = wmCloseX(w);
    int cy = wmCloseY(w);
    if (px >= cx && px < cx + WM_CLOSE_SIZE && py >= cy && py < cy + WM_CLOSE_SIZE)
        return WM_PART_CLOSE;
    return WM_PART_TITLE;
}

/// The topmost window whose frame is under a screen position, -1 if there is none.
int wmWindowAt(int x, int y)
{
    for (int i = wmCount - 1; i >= 0; i--)
    {
        int idx = wmOrder[i];
        if (wmHitPart(idx, x, y) != WM_PART_NONE)
            return idx;
    }
    return -1;
}

// damage

/// Something changed on screen: x, y, w, h in screen coordinates (render.d clips them).
void wmAddDamage(int x, int y, int w, int h)
{
    if (w <= 0 || h <= 0)
        return;
    if (!wmHasDamage)
    {
        wmHasDamage = true;
        wmDx0 = x;
        wmDy0 = y;
        wmDx1 = x + w;
        wmDy1 = y + h;
        return;
    }
    if (x < wmDx0) wmDx0 = x;
    if (y < wmDy0) wmDy0 = y;
    if (x + w > wmDx1) wmDx1 = x + w;
    if (y + h > wmDy1) wmDy1 = y + h;
}

/// The frame of window `idx` (decoration included) has to be redrawn.
void wmDamageFrame(int idx)
{
    const(WmWindow)* w = &wmWindows[idx];
    wmAddDamage(wmFrameX(w), wmFrameY(w), wmFrameW(w), wmFrameH(w));
}

/// Hands over (and forgets) what changed since the last call. False if nothing did.
bool wmTakeDamage(int* x, int* y, int* w, int* h)
{
    if (!wmHasDamage)
        return false;
    wmHasDamage = false;
    *x = wmDx0;
    *y = wmDy0;
    *w = wmDx1 - wmDx0;
    *h = wmDy1 - wmDy0;
    return true;
}

// windows

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

private void wmSendClose(int idx)
{
    GfxEvent e;
    e.type = GFX_EV_CLOSE;
    ugfxSend(wmWindows[idx].surface, &e);
}

/// Gives the keyboard to window `idx` (-1: nobody). The windows are told, the frames redrawn.
void wmSetFocus(int idx)
{
    if (idx == wmFocus)
        return;
    if (wmFocus >= 0)
    {
        wmSendFocus(wmFocus, 0);
        wmDamageFrame(wmFocus);
    }
    wmFocus = idx;
    if (idx >= 0)
    {
        wmSendFocus(idx, 1);
        wmDamageFrame(idx);
    }
}

/// Puts window `idx` at the front of its layer: wmOrder is sorted by layer (BOTTOM, ordinary, TOP),
/// so it goes in front of every window of its own layer and of the ones below, but not of a higher one.
/// `idx` may or may not be in wmOrder already. Does not report damage.
private void wmRestack(int idx)
{
    int j = 0;
    for (int i = 0; i < wmCount; i++)
        if (wmOrder[i] != idx)
            wmOrder[j++] = wmOrder[i];
    wmCount = j;

    int layer = wmLayer(&wmWindows[idx]);
    int pos = 0;
    while (pos < wmCount && wmLayer(&wmWindows[wmOrder[pos]]) <= layer)
        pos++;
    for (int i = wmCount; i > pos; i--)
        wmOrder[i] = wmOrder[i - 1];
    wmOrder[pos] = idx;
    wmCount++;
}

/// Moves window `idx` in front of all others of its layer (see wmRestack).
void wmRaise(int idx)
{
    // Already in front? Then it is the last window that is not in a higher layer.
    int layer = wmLayer(&wmWindows[idx]);
    int last = -1;
    for (int i = 0; i < wmCount && wmLayer(&wmWindows[wmOrder[i]]) <= layer; i++)
        last = i;
    if (last >= 0 && wmOrder[last] == idx)
        return;
    wmRestack(idx);
    wmDamageFrame(idx);
}

/// Limits a position of a decorated window so that part of its title bar stays on screen.
void wmClampPosition(const(WmWindow)* w, int* nx, int* ny)
{
    int minY = WM_TITLE_H + WM_BORDER + WM_OUTLINE;     // the outline stays on screen, too
    if (*ny < minY)
        *ny = minY;
    if (*ny > wmScreenH - WM_TITLE_H)
        *ny = wmScreenH - WM_TITLE_H;
    int keep = 3 * WM_TITLE_H;
    if (*nx < keep - w.canvas.width)
        *nx = keep - w.canvas.width;
    if (*nx > wmScreenW - keep)
        *nx = wmScreenW - keep;
}

/// Moves window `idx` so that its drawable area starts at nx, ny. Keeps part of the title bar on screen.
void wmMoveWindow(int idx, int nx, int ny)
{
    WmWindow* w = &wmWindows[idx];
    wmClampPosition(w, &nx, &ny);
    if (nx == w.x && ny == w.y)
        return;
    wmDamageFrame(idx);                     // where it was
    w.x = nx;
    w.y = ny;
    wmDamageFrame(idx);                     // where it is now
}

/// If `edge` is within WM_SNAP_DIST of `target` and closer than what was found so far, remember the
/// shift that brings it there.
private void wmSnapTry(int edge, int target, int* shift, int* bestDist)
{
    int d = target - edge;
    int a = (d < 0) ? -d : d;
    if (a <= WM_SNAP_DIST && a < *bestDist)
    {
        *bestDist = a;
        *shift = d;
    }
}

/**
 * Window snapping: adjusts a wanted position (drawable area, nx, ny) of window `idx` so that the
 * edges of its frame line up with the screen edges and with the frames of the other windows when
 * they are within WM_SNAP_DIST. Per axis, the closest edge wins. Windows only snap to each other
 * if they are next to or across from one another (their extent on the other axis overlaps or is
 * within WM_SNAP_DIST), so a window does not jump to a neighbour on the other side of the screen.
 * Both "touching" (my right edge to your left edge) and "aligned" (left edge to left edge) count.
 */
private void wmSnapPosition(int idx, int* nx, int* ny)
{
    const(WmWindow)* w = &wmWindows[idx];
    int l = *nx - (w.x - wmFrameX(w));
    int t = *ny - (w.y - wmFrameY(w));
    int r = l + wmFrameW(w);
    int b = t + wmFrameH(w);

    int dx = 0;
    int dy = 0;
    int bestX = WM_SNAP_DIST + 1;
    int bestY = WM_SNAP_DIST + 1;

    wmSnapTry(l, 0, &dx, &bestX);
    wmSnapTry(r, wmScreenW, &dx, &bestX);
    wmSnapTry(t, 0, &dy, &bestY);
    wmSnapTry(b, wmScreenH, &dy, &bestY);

    for (int i = 0; i < wmCount; i++)
    {
        int o = wmOrder[i];
        if (o == idx)
            continue;
        const(WmWindow)* ow = &wmWindows[o];
        int ol = wmFrameX(ow);
        int ot = wmFrameY(ow);
        int or_ = ol + wmFrameW(ow);
        int ob = ot + wmFrameH(ow);

        if (t < ob + WM_SNAP_DIST && b > ot - WM_SNAP_DIST)     // level with it: snap horizontally
        {
            wmSnapTry(l, or_, &dx, &bestX);
            wmSnapTry(r, ol, &dx, &bestX);
            wmSnapTry(l, ol, &dx, &bestX);
            wmSnapTry(r, or_, &dx, &bestX);
        }
        if (l < or_ + WM_SNAP_DIST && r > ol - WM_SNAP_DIST)    // above or below it: snap vertically
        {
            wmSnapTry(t, ob, &dy, &bestY);
            wmSnapTry(b, ot, &dy, &bestY);
            wmSnapTry(t, ot, &dy, &bestY);
            wmSnapTry(b, ob, &dy, &bestY);
        }
    }
    *nx += dx;
    *ny += dy;
}

/// Moves window `idx` for a title bar drag to the wanted position, snapping it if that is switched on.
/// The wanted position always comes straight from the mouse, so a snapped window lets go as soon as
/// the mouse is more than WM_SNAP_DIST away.
private void wmDragWindow(int idx, int nx, int ny)
{
    if (wmSnapEnabled)
    {
        wmClampPosition(&wmWindows[idx], &nx, &ny);     // snap what will really be shown
        wmSnapPosition(idx, &nx, &ny);
    }
    wmMoveWindow(idx, nx, ny);                          // clamps again
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
    w.flags = 0;                            // ordinary until the client sends GFX_EV_WM_HINTS
    w.x = 40 + (wmCascade % 8) * 32;
    w.y = 60 + (wmCascade % 8) * 32;
    wmCascade++;

    wmRestack(slot);
    wmDamageFrame(slot);
    wmSetFocus(slot);                       // new windows get the keyboard
    return slot;
}

/**
 * A client asked for special treatment (GFX_EV_WM_HINTS): `flags` are GFX_WIN_*, and with
 * GFX_WIN_POSITION the drawable area goes to x, y. Everything about the window that depends
 * on the flags (frame, layer, who may move it) is updated, and the old and new places redrawn.
 */
void wmSetHints(int idx, uint flags, int x, int y)
{
    WmWindow* w = &wmWindows[idx];
    flags &= GFX_WIN_ALL;
    if ((flags & GFX_WIN_TOP) != 0)
        flags &= ~GFX_WIN_BOTTOM;           // both do not make sense: TOP wins

    wmDamageFrame(idx);                     // the frame as it was
    bool layerChanged = wmLayer(w) != wmLayerOfFlags(flags);
    w.flags = flags;

    if ((flags & GFX_WIN_POSITION) != 0)
    {
        if (wmDecorated(w))
            wmClampPosition(w, &x, &y);     // do not lose a title bar off screen. A shell window may go anywhere
        w.x = x;
        w.y = y;
    }

    // Nothing that was going on with the old frame may continue
    if (wmDrag == idx && (wmIsFixed(w) || !wmDecorated(w)))
        wmDrag = -1;
    if (wmCloseArmed == idx && !wmDecorated(w))
        wmCloseArmed = -1;

    if (layerChanged)
        wmRestack(idx);                     // otherwise it keeps its place among the windows

    // A shell window should not keep the keyboard it got as a new window if someone else can have it
    if (wmFocus == idx && wmIsBottom(w))
    {
        for (int i = wmCount - 1; i >= 0; i--)
        {
            if (!wmIsBottom(&wmWindows[wmOrder[i]]))
            {
                wmSetFocus(wmOrder[i]);
                break;
            }
        }
    }
    wmDamageFrame(idx);                     // the frame as it is now
}

/// The program that owned the surface is gone (GFX_EV_SURFACE_GONE).
void wmRemove(uint surface)
{
    int idx = wmFind(surface);
    if (idx >= 0)
    {
        wmDamageFrame(idx);                 // the place it leaves has to be redrawn

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
        if (wmDrag == idx)
            wmDrag = -1;
        if (wmCloseArmed == idx)
            wmCloseArmed = -1;
        if (wmFocus == idx)
        {
            wmFocus = -1;                   // the window is gone, no FOCUS event for it
            wmSetFocus(wmCount > 0 ? wmOrder[wmCount - 1] : -1);
        }
    }
    // The kernel keeps the memory until we say we are done with it
    ugfxServerUnmap(surface);
}

// input

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

    // A window is being dragged: the mouse belongs to the window manager until the button is up
    if (wmDrag >= 0)
    {
        wmDragWindow(wmDrag, wmMouseX - wmDragDx, wmMouseY - wmDragDy);
        if (buttons == 0)
        {
            wmDrag = -1;
            wmGrab = -1;
        }
        return;
    }

    // The close button is pressed: it only counts if the button is released on it, too
    if (wmCloseArmed >= 0)
    {
        if (buttons == 0)
        {
            if (wmHitPart(wmCloseArmed, wmMouseX, wmMouseY) == WM_PART_CLOSE)
                wmSendClose(wmCloseArmed);
            wmCloseArmed = -1;
            wmGrab = -1;
        }
        return;
    }

    int hit = wmWindowAt(wmMouseX, wmMouseY);
    int part = (hit >= 0) ? wmHitPart(hit, wmMouseX, wmMouseY) : WM_PART_NONE;

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
        wmGrabClient = (part == WM_PART_CLIENT);

        if ((pressed & GFX_BTN_LEFT) != 0)
        {
            if (part == WM_PART_TITLE && !wmIsFixed(&wmWindows[hit]))
            {
                wmDrag = hit;
                wmDragDx = wmMouseX - wmWindows[hit].x;
                wmDragDy = wmMouseY - wmWindows[hit].y;
                return;
            }
            if (part == WM_PART_CLOSE)
            {
                wmCloseArmed = hit;
                return;
            }
        }
    }

    // Only the drawable area belongs to the client; the decoration is ours
    int target = -1;
    if (wmGrab >= 0)
    {
        if (wmGrabClient)
            target = wmGrab;
    }
    else if (part == WM_PART_CLIENT)
        target = hit;

    if (target >= 0)
    {
        GfxEvent fwd = *ev;
        fwd.a = wmMouseX - wmWindows[target].x;     // relative to the window's drawable area
        fwd.b = wmMouseY - wmWindows[target].y;
        ugfxSend(wmWindows[target].surface, &fwd);
    }

    if (buttons == 0)
        wmGrab = -1;
}

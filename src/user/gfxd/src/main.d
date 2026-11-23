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
 * GFXD - the graphics server.
 *
 * Start it from the kernel shell with `gfx start` (or `run gfxd &`). It takes the screen
 * at once. Ctrl+F1 switches back to the shell, Ctrl+F2 back to the server, Ctrl+F3 kills
 * it - those keys are handled by the kernel, whatever this program is doing. Ctrl+Q (below)
 * ends it politely.
 *
 * Everything it does is a reaction to events from ugfxPoll():
 *   GFX_EV_SURFACE_NEW / _DAMAGE / _GONE   programs and their drawable areas   -> wm.d
 *   GFX_EV_VISIBLE                          the screen was given / taken away
 *   GFX_EV_KEY / GFX_EV_MOUSE               input, only while we have the screen -> wm.d
 * and then, when something changed, a new picture is composed (render.d) and presented.
 *
 * Messages printed with uputs() land on the shell's screen: read them after Ctrl+F1.
 */

import ulib.dios;
import ulib.gfx;
import wm;
import render;

enum ulong FRAME_MS = 16;           // at most ~60 pictures per second

__gshared bool running = true;
__gshared bool sceneDirty = true;   // the whole screen is out of date (start, screen regained)
__gshared bool cursorDirty;         // only the mouse moved: cheap update

void handleEvent(const(GfxEvent)* ev)
{
    switch (ev.type)
    {
        case GFX_EV_SURFACE_NEW:
            wmAdd(ev.surface, cast(uint)ev.c);
            break;

        case GFX_EV_SURFACE_DAMAGE:
            // ev.a, ev.b, ev.c, ev.d: the rectangle that changed, relative to the surface.
        {
            int idx = wmFind(ev.surface);
            if (idx >= 0)
                renderAddDamage(wmWindows[idx].x + ev.a, wmWindows[idx].y + ev.b, ev.c, ev.d);
            break;
        }

        case GFX_EV_SURFACE_GONE:
            wmRemove(ev.surface);
            break;

        case GFX_EV_VISIBLE:
            renderVisible = ev.a != 0;
            sceneDirty = true;          // when we get the screen back it must be repainted fully
            break;

        case GFX_EV_KEY:
            if ((ev.c & GFX_MOD_CTRL) != 0 && ev.b == 17)   // Ctrl+Q (ASCII control code 17)
                running = false;
            else
                wmHandleKey(ev);
            break;

        case GFX_EV_MOUSE:
            wmHandleMouse(ev);
            cursorDirty = true;         // the cursor moved (a drag or click may also change the scene: see wmTakeDamage)
            break;

        default:
            break;
    }
}

int main(string[] args)
{
    GfxInfo info;
    if (ugfxInfo(&info) != 0)
    {
        uputs("gfxd: no graphics available\n");
        return 1;
    }
    if (!renderInit(info.width, info.height))
    {
        uputs("gfxd: out of memory for the back buffer\n");
        return 1;
    }
    wmInit(cast(int)info.width, cast(int)info.height);

    // From here on we own the screen. Programs that are already running are announced
    // as GFX_EV_SURFACE_NEW, the first event is for them.
    if (ugfxServerBegin() != 0)
    {
        uputs("gfxd: a graphics server is already running\n");
        return 1;
    }
    uputs("gfxd: started. Ctrl+F1 shell, Ctrl+F2 server, Ctrl+F3 kill it, Ctrl+Q quit\n");

    ulong lastFrame = 0;
    while (running)
    {
        // Sleep until something happens - but when a picture is due, only until it is time.
        long timeout = -1;
        bool pending = sceneDirty || cursorDirty || renderHasDamage;
        if (pending && renderVisible)
        {
            ulong since = uticks() - lastFrame;
            timeout = (since >= FRAME_MS) ? 0 : cast(long)(FRAME_MS - since);
        }

        GfxEvent ev;
        int got = ugfxPoll(&ev, timeout);
        while (got == 1)
        {
            handleEvent(&ev);
            got = ugfxPoll(&ev, 0);     // everything that is already waiting
        }
        if (got < 0)
            break;                      // not the server any more

        // What the window manager changed (moves, raising, focus, new/gone windows)
        int dx, dy, dw, dh;
        if (wmTakeDamage(&dx, &dy, &dw, &dh))
            renderAddDamage(dx, dy, dw, dh);

        pending = sceneDirty || cursorDirty || renderHasDamage;
        if (pending && renderVisible && uticks() - lastFrame >= FRAME_MS)
        {
            if (sceneDirty)
            {
                renderFrame();              // start or screen regained: recompose and present everything
            }
            else
            {
                if (renderHasDamage)
                    renderFlushDamage();    // window content: only the changed area
                if (cursorDirty)
                    renderCursorMove();     // two small rectangles
            }
            sceneDirty = false;
            cursorDirty = false;
            lastFrame = uticks();
        }
    }

    ugfxServerEnd();                    // the shell gets the screen back
    uputs("gfxd: stopped\n");
    return 0;
}

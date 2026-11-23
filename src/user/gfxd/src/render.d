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

module render;

/**
 * The compositor. Two buffers, both the size of the screen, in ordinary memory:
 *
 *   renderScene   desktop + windows, WITHOUT the mouse cursor
 *   renderScreen  what the screen shows: the scene plus the cursor; this is what is presented
 *
 * Two kinds of update, because they cost very differently:
 *
 *   renderFrame()       something in the scene changed (window content, order, focus):
 *                       recompose everything, copy it to renderScreen, present it all.
 *   renderCursorMove()  only the mouse moved: restore the pixels under the old cursor from
 *                       the scene, draw the cursor at the new place, present just those two
 *                       small rectangles.
 *
 * Further steps when this is not fast enough: recompose and present only the damage
 * rectangle of a window (GFX_EV_SURFACE_DAMAGE, moved by the window position).
 *
 * Image loading, fonts, window decorations, alpha blending: all of that goes here.
 */

import ulib.dios;
import ulib.gfx;
import wm;
import cursor;

enum uint COLOR_DESKTOP      = 0x00203A5A;
enum uint COLOR_BORDER       = 0x00707070;
enum uint COLOR_BORDER_FOCUS = 0x00FFC040;
enum uint CURSOR_KEY         = 0x00FF00FF;      // transparent pixels in cursor.d

__gshared Canvas renderScene;       // desktop and windows, no cursor
__gshared Canvas renderScreen;      // scene + cursor: what is presented
__gshared bool renderVisible;       // does the server have the screen? (GFX_EV_VISIBLE)
__gshared bool renderCursorDrawn;   // is there a cursor in renderScreen, and where:
__gshared int renderCursorX;
__gshared int renderCursorY;

private bool renderAlloc(Canvas* c, uint width, uint height)
{
    void* mem = umalloc(cast(size_t)width * cast(size_t)height * 4);
    if (mem is null)
        return false;
    c.pixels = cast(uint*)mem;
    c.width = cast(int)width;
    c.height = cast(int)height;
    c.stride = cast(int)width;
    c.clear(COLOR_DESKTOP);
    return true;
}

/// Allocates both buffers. False if there is no memory for them.
bool renderInit(uint width, uint height)
{
    renderCursorDrawn = false;
    return renderAlloc(&renderScene, width, height) && renderAlloc(&renderScreen, width, height);
}

// Draws the cursor into renderScreen: clip once, then walk rows (no per-pixel checks).
private void renderCursorDraw(int x, int y)
{
    int cx0 = (x < 0) ? -x : 0;
    int cy0 = (y < 0) ? -y : 0;
    int cx1 = (x + CURSOR_WIDTH > renderScreen.width) ? renderScreen.width - x : CURSOR_WIDTH;
    int cy1 = (y + CURSOR_HEIGHT > renderScreen.height) ? renderScreen.height - y : CURSOR_HEIGHT;

    for (int cy = cy0; cy < cy1; cy++)
    {
        const(uint)* src = CURSOR.ptr + cy * CURSOR_WIDTH;
        uint* dst = renderScreen.pixels + cast(size_t)(y + cy) * cast(size_t)renderScreen.stride + x;
        for (int cx = cx0; cx < cx1; cx++)
        {
            uint pix = src[cx];
            if (pix != CURSOR_KEY)
                dst[cx] = pix;
        }
    }
    renderCursorDrawn = true;
    renderCursorX = x;
    renderCursorY = y;
}

// Copies a rectangle of renderScreen to the screen. (Does nothing while the shell has it.)
private void renderPresentRect(int x, int y, int w, int h)
{
    GfxRect r;
    r.x = x;
    r.y = y;
    r.w = w;
    r.h = h;
    ugfxServerPresent(renderScreen.pixels, &r, 0);
}

/// Recomposes the whole picture and presents all of it.
void renderFrame()
{
    // back to front
    renderScene.clear(COLOR_DESKTOP);
    for (int i = 0; i < wmCount; i++)
    {
        int idx = wmOrder[i];
        WmWindow* w = &wmWindows[idx];
        uint border = (idx == wmFocus) ? COLOR_BORDER_FOCUS : COLOR_BORDER;
        renderScene.rect(w.x - 1, w.y - 1, w.canvas.width + 2, w.canvas.height + 2, border);
        renderScene.blit(&w.canvas, w.x, w.y);
    }

    // The kernel does not draw the mouse cursor while we have the screen: it is ours.
    renderScreen.blit(&renderScene, 0, 0);
    renderCursorDraw(wmMouseX, wmMouseY);
    ugfxServerPresent(renderScreen.pixels, null, 0);
}

/// Only the mouse moved: update just the pixels around the old and the new cursor.
/// Call renderFrame() first at least once (and whenever the scene changes).
void renderCursorMove()
{
    if (renderCursorDrawn)
    {
        // erase: put the scene back under the old cursor
        int ox = renderCursorX;
        int oy = renderCursorY;
        renderScreen.blitRect(&renderScene, ox, oy, CURSOR_WIDTH, CURSOR_HEIGHT, ox, oy);
        renderCursorDraw(wmMouseX, wmMouseY);
        renderPresentRect(ox, oy, CURSOR_WIDTH, CURSOR_HEIGHT);
    }
    else
        renderCursorDraw(wmMouseX, wmMouseY);
    renderPresentRect(wmMouseX, wmMouseY, CURSOR_WIDTH, CURSOR_HEIGHT);
}

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
 * Three kinds of update, because they cost very differently:
 *
 *   renderFrame()        the layout changed (window added/removed/raised, focus, screen regained):
 *                        recompose everything, copy it to renderScreen, present it all.
 *   renderFlushDamage()  a window drew something (GFX_EV_SURFACE_DAMAGE): the changed
 *                        rectangles are collected with renderAddDamage(); this recomposes,
 *                        copies and presents only their bounding box.
 *   renderCursorMove()   only the mouse moved: restore the pixels under the old cursor from
 *                        the scene, draw the cursor at the new place, present just those two
 *                        small rectangles.
 *
 * Further steps when this is not fast enough: keep a LIST of damage rectangles instead of one
 * bounding box (two animated windows far apart currently cost the area between them), and
 * skip windows that are completely covered.
 *
 * Image loading, fonts, window decorations, alpha blending: all of that goes here.
 */

import ulib.dios;
import ulib.gfx;
import wm;
import cursor;

enum uint COLOR_DESKTOP      = 0x00203A5A;
enum uint COLOR_FRAME        = 0x00E4E4E4;
enum uint COLOR_FRAME_FOCUS  = 0x00EBEBEB;
enum uint COLOR_CLOSE        = 0x00DC5050;
enum uint COLOR_CLOSE_X      = 0x00FFFFFF;

__gshared Canvas renderScene;       // desktop and windows, no cursor
__gshared Canvas renderScreen;      // scene + cursor: what is presented
__gshared bool renderVisible;       // does the server have the screen? (GFX_EV_VISIBLE)
__gshared bool renderCursorDrawn;   // is there a cursor in renderScreen, and where:
__gshared int renderCursorX;
__gshared int renderCursorY;

// Pending damage: bounding box in screen coordinates, half open [x0, x1) x [y0, y1)
__gshared bool renderHasDamage;
__gshared int renderDx0;
__gshared int renderDy0;
__gshared int renderDx1;
__gshared int renderDy1;

__gshared bool haveCursor;

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
    haveCursor = loadCursor();
    return renderAlloc(&renderScene, width, height) && renderAlloc(&renderScreen, width, height);
}

/// Releases rendering resources.
void renderRelease()
{
    deleteCursor();
}

// Alpha blending of a cursor pixel (0xAARRGGBB, straight alpha) over a screen pixel.
// x / 255 rounded to nearest, without a division.
private uint div255(uint x) @nogc nothrow
{
    x += 128;
    return (x + (x >> 8)) >> 8;
}

private uint blendCursorPixel(uint src, uint dst) @nogc nothrow
{
    uint a = src >> 24;
    uint ia = 255 - a;
    uint r = div255(((src >> 16) & 0xFF) * a + ((dst >> 16) & 0xFF) * ia);
    uint g = div255(((src >> 8) & 0xFF) * a + ((dst >> 8) & 0xFF) * ia);
    uint b = div255((src & 0xFF) * a + (dst & 0xFF) * ia);
    return (r << 16) | (g << 8) | b;
}

// Draws the cursor into renderScreen: clip once, then walk rows (no per-pixel checks).
// Pixels are alpha blended over the scene: alpha 0 leaves the screen alone, 255 replaces it,
// anything in between (anti-aliased edges, shadows) mixes the two.
private void renderCursorDraw(int x, int y)
{
    if (!haveCursor)
        // TODO: draw a fallback cursor
        return;
    
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
            uint a = pix >> 24;
            if (a == 0)
                continue;
            dst[cx] = (a == 255) ? (pix & 0x00FFFFFF) : blendCursorPixel(pix, dst[cx]);
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

// The frame of a window: border and title bar in one colour, a close button on the title bar.
// `c` is a view of the scene that starts at rx, ry: coordinates are shifted by that.
// A title (text) would go here, as soon as there is a font.
private void renderDecoration(Canvas* c, const(WmWindow)* w, bool focused, int rx, int ry)
{
    c.fillRect(wmFrameX(w) - rx, wmFrameY(w) - ry, wmFrameW(w), wmFrameH(w),
               focused ? COLOR_FRAME_FOCUS : COLOR_FRAME);

    int bx = wmCloseX(w) - rx;
    int by = w.y - WM_TITLE_H - ry;
    c.fillRect(bx + 2, by + 2, WM_TITLE_H - 4, WM_TITLE_H - 4, COLOR_CLOSE);
    c.line(bx + 6, by + 6, bx + WM_TITLE_H - 7, by + WM_TITLE_H - 7, COLOR_CLOSE_X);
    c.line(bx + WM_TITLE_H - 7, by + 6, bx + 6, by + WM_TITLE_H - 7, COLOR_CLOSE_X);
}

// Recomposes the part rx, ry, rw, rh (inside the screen) of the scene: desktop first, then the
// windows back to front. Everything is drawn on a clipped view of the scene (Canvas.sub), so a
// window that only partly overlaps the rectangle just contributes its overlapping part.
private void renderScenePart(int rx, int ry, int rw, int rh)
{
    Canvas c = renderScene.sub(rx, ry, rw, rh);
    if (!c.valid())
        return;
    c.clear(COLOR_DESKTOP);
    for (int i = 0; i < wmCount; i++)
    {
        int idx = wmOrder[i];
        WmWindow* w = &wmWindows[idx];
        if (wmDecorated(w))
            renderDecoration(&c, w, idx == wmFocus, rx, ry);
        c.blit(&w.canvas, w.x - rx, w.y - ry);
    }
}

/// A window changed: x, y, w, h in SCREEN coordinates. Collected until renderFlushDamage().
void renderAddDamage(int x, int y, int w, int h)
{
    int x0 = (x < 0) ? 0 : x;
    int y0 = (y < 0) ? 0 : y;
    int x1 = (x + w > renderScreen.width) ? renderScreen.width : x + w;
    int y1 = (y + h > renderScreen.height) ? renderScreen.height : y + h;
    if (x0 >= x1 || y0 >= y1)
        return;
    if (!renderHasDamage)
    {
        renderHasDamage = true;
        renderDx0 = x0;
        renderDy0 = y0;
        renderDx1 = x1;
        renderDy1 = y1;
        return;
    }
    if (x0 < renderDx0) renderDx0 = x0;
    if (y0 < renderDy0) renderDy0 = y0;
    if (x1 > renderDx1) renderDx1 = x1;
    if (y1 > renderDy1) renderDy1 = y1;
}

/// Recomposes the whole picture and presents all of it.
void renderFrame()
{
    renderHasDamage = false;            // everything is redrawn anyway
    renderScenePart(0, 0, renderScene.width, renderScene.height);

    // The kernel does not draw the mouse cursor while we have the screen: it is ours.
    renderScreen.blit(&renderScene, 0, 0);
    renderCursorDraw(wmMouseX, wmMouseY);
    ugfxServerPresent(renderScreen.pixels, null, 0);
}

/// Recomposes, copies and presents only what renderAddDamage() collected.
void renderFlushDamage()
{
    if (!renderHasDamage)
        return;
    renderHasDamage = false;
    int x = renderDx0;
    int y = renderDy0;
    int w = renderDx1 - renderDx0;
    int h = renderDy1 - renderDy0;

    renderScenePart(x, y, w, h);
    renderScreen.blitRect(&renderScene, x, y, w, h, x, y);

    // The copy wiped the cursor if it was in there: put it back where it was drawn (a pending
    // mouse move is renderCursorMove's business)
    if (renderCursorDrawn && renderCursorX < x + w && renderCursorX + CURSOR_WIDTH > x
        && renderCursorY < y + h && renderCursorY + CURSOR_HEIGHT > y)
        renderCursorDraw(renderCursorX, renderCursorY);

    renderPresentRect(x, y, w, h);
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

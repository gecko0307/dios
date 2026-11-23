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
 * The compositor: draws the desktop and the windows into a back buffer (the whole screen in
 * ordinary memory) and has the kernel copy it to the screen.
 *
 * It is a plain "painter's algorithm" redraw of everything, every time. That is simple and
 * fast enough to start with; when it is not, the damage events (and ugfxServerPresent's
 * rectangle argument) are the way to redraw and copy only what changed.
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

__gshared Canvas renderScreen; // the back buffer
__gshared bool renderVisible;  // does the server have the screen? (GFX_EV_VISIBLE)

/// Allocates the back buffer. False if there is no memory for it.
bool renderInit(uint width, uint height)
{
    void* mem = umalloc(cast(size_t)width * cast(size_t)height * 4);
    if (mem is null)
        return false;
    renderScreen.pixels = cast(uint*)mem;
    renderScreen.width = cast(int)width;
    renderScreen.height = cast(int)height;
    renderScreen.stride = cast(int)width;
    renderScreen.clear(COLOR_DESKTOP);
    return true;
}

private void renderCursor(int x, int y)
{
    /*
    for (int r = 0; r < 12; r++)
    {
        renderScreen.fillRect(x, y + r, r + 1, 1, 0x00000000);
        if (r > 1 && r < 11)
            renderScreen.fillRect(x + 1, y + r, r - 1, 1, 0x00FFFFFF);
    }
    */
    
    for (int cy = 0; cy < CURSOR_HEIGHT; cy++)
    for (int cx = 0; cx < CURSOR_WIDTH; cx++)
    {
        uint pix = CURSOR[cast(size_t)(cy * CURSOR_WIDTH + cx)];
        if (pix != 0x00FF00FF)
            renderScreen.setPixel(x + cx, y + cy, pix);
    }
}

/// Draws the whole picture into the back buffer.
void renderFrame()
{
    renderScreen.clear(COLOR_DESKTOP);

    // back to front
    for (int i = 0; i < wmCount; i++)
    {
        int idx = wmOrder[i];
        WmWindow* w = &wmWindows[idx];
        uint border = (idx == wmFocus) ? COLOR_BORDER_FOCUS : COLOR_BORDER;
        renderScreen.rect(w.x - 1, w.y - 1, w.canvas.width + 2, w.canvas.height + 2, border);
        renderScreen.blit(&w.canvas, w.x, w.y);
    }

    // The kernel doesn't draw the mouse cursor while we have the screen, draw our own
    renderCursor(wmMouseX, wmMouseY);
}

/// Copies the back buffer to the screen. (Does nothing while the shell has it.)
void renderPresent()
{
    ugfxServerPresent(renderScreen.pixels, null, 0);
}

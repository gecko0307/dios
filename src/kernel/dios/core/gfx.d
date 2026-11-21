module dios.core.gfx;

/**
 * Software "compositor" with damage tracking.
 *   scene - an ordinary RAM buffer holding the complete picture WITHOUT the
 *           mouse cursor. GUI is drawn into it.
 *   front - the real framebuffer (slow write-combined video memory).
 *
 * Drawing code calls gfxDirty(rect) for every area it changed. gfxPresent()
 * copies only those rectangles from scene to front, then draws the mouse
 * cursor on top (composed in a small temporary buffer, so each cursor row is
 * one write to video memory).
 */
import dios.core.framebuffer;
import dios.core.mem;
import dios.core.mouse;
import dios.core.cursor;

enum uint GFX_MAX_DIRTY = 16;

struct GfxRect
{
    int x0, y0, x1, y1; // x1/y1 are exclusive
}

struct GfxState
{
    Framebuffer* front;
    Framebuffer* scene;
    GfxRect[GFX_MAX_DIRTY] dirty;
    uint numDirty;
    bool fullDirty;
    bool mouseDrawn;
    int mouseX, mouseY; // where the cursor was last drawn
    bool ready;
}

__gshared GfxState gfx;
__gshared uint[64] gfxRowTmp; // one cursor row (cursor must be <= 64 px wide)

extern(C):

void gfxInit(Framebuffer* front, Framebuffer* scene) @nogc nothrow
{
    gfx = GfxState.init;
    gfx.front = front;
    gfx.scene = scene;
    gfx.fullDirty = true; // first present copies everything
    gfx.ready = true;
}

// Clip a rectangle to the screen. Returns false if nothing is left.
bool gfxClip(int* x0, int* y0, int* x1, int* y1) @nogc nothrow
{
    if (*x0 < 0) *x0 = 0;
    if (*y0 < 0) *y0 = 0;
    if (*x1 > cast(int)gfx.scene.width) *x1 = cast(int)gfx.scene.width;
    if (*y1 > cast(int)gfx.scene.height) *y1 = cast(int)gfx.scene.height;
    return *x0 < *x1 && *y0 < *y1;
}

// Record that scene pixels in [x, x+w) x [y, y+h) have changed.
void gfxDirty(int x, int y, int w, int h) @nogc nothrow
{
    if (!gfx.ready || gfx.fullDirty)
        return;

    int x0 = x, y0 = y, x1 = x + w, y1 = y + h;
    if (!gfxClip(&x0, &y0, &x1, &y1))
        return;

    // Merge with an overlapping/touching rectangle (consecutive characters on
    // one line collapse into one wide rectangle this way).
    for (uint i = 0; i < gfx.numDirty; i++)
    {
        GfxRect* r = &gfx.dirty[i];
        if (x0 <= r.x1 && x1 >= r.x0 && y0 <= r.y1 && y1 >= r.y0)
        {
            if (x0 < r.x0) r.x0 = x0;
            if (y0 < r.y0) r.y0 = y0;
            if (x1 > r.x1) r.x1 = x1;
            if (y1 > r.y1) r.y1 = y1;
            return;
        }
    }

    if (gfx.numDirty == GFX_MAX_DIRTY)
    {
        // List full: collapse everything into one bounding box.
        GfxRect b = gfx.dirty[0];
        for (uint i = 1; i < gfx.numDirty; i++)
        {
            if (gfx.dirty[i].x0 < b.x0) b.x0 = gfx.dirty[i].x0;
            if (gfx.dirty[i].y0 < b.y0) b.y0 = gfx.dirty[i].y0;
            if (gfx.dirty[i].x1 > b.x1) b.x1 = gfx.dirty[i].x1;
            if (gfx.dirty[i].y1 > b.y1) b.y1 = gfx.dirty[i].y1;
        }
        gfx.dirty[0] = b;
        gfx.numDirty = 1;
    }
    gfx.dirty[gfx.numDirty].x0 = x0;
    gfx.dirty[gfx.numDirty].y0 = y0;
    gfx.dirty[gfx.numDirty].x1 = x1;
    gfx.dirty[gfx.numDirty].y1 = y1;
    gfx.numDirty++;
}

// XOR a rectangle of the scene with `mask`. Doing it twice restores the
// original pixels exactly, which makes it ideal for a blinking text cursor.
void gfxXorRect(int x, int y, int w, int h, uint mask) @nogc nothrow
{
    int x0 = x, y0 = y, x1 = x + w, y1 = y + h;
    if (!gfx.ready || !gfxClip(&x0, &y0, &x1, &y1))
        return;
    uint stride = gfx.scene.pitch / gfx.scene.bytesPerPixel;
    for (int yy = y0; yy < y1; yy++)
    {
        uint* row = gfx.scene.ptr + cast(size_t)yy * stride;
        for (int xx = x0; xx < x1; xx++)
            row[xx] ^= mask;
    }
    gfxDirty(x0, y0, x1 - x0, y1 - y0);
}

// Copy one rectangle scene -> front, row by row.
void gfxBlitRect(int x0, int y0, int x1, int y1) @nogc nothrow
{
    if (!gfxClip(&x0, &y0, &x1, &y1))
        return;
    uint sstride = gfx.scene.pitch / gfx.scene.bytesPerPixel;
    uint fstride = gfx.front.pitch / gfx.front.bytesPerPixel;
    size_t bytes = cast(size_t)(x1 - x0) * 4;
    for (int y = y0; y < y1; y++)
        memcpy(gfx.front.ptr + cast(size_t)y * fstride + x0,
               gfx.scene.ptr + cast(size_t)y * sstride + x0, bytes);
}

// Draw the mouse cursor at (mx, my) on the front buffer: scene pixels with the
// sprite blended over them (colour key 0x00FF00FF), written one row at a time.
void gfxDrawCursor(int mx, int my) @nogc nothrow
{
    int w = CURSOR_WIDTH, h = CURSOR_HEIGHT;
    if (w > 64)
        return;
    int x0 = mx, y0 = my, x1 = mx + w, y1 = my + h;
    if (!gfxClip(&x0, &y0, &x1, &y1))
        return;

    uint sstride = gfx.scene.pitch / gfx.scene.bytesPerPixel;
    uint fstride = gfx.front.pitch / gfx.front.bytesPerPixel;
    int cw = x1 - x0;
    for (int y = y0; y < y1; y++)
    {
        memcpy(gfxRowTmp.ptr, gfx.scene.ptr + cast(size_t)y * sstride + x0, cast(size_t)cw * 4);
        for (int x = 0; x < cw; x++)
        {
            uint pix = CURSOR[cast(size_t)(y - my) * w + (x0 - mx) + x];
            if (pix != 0x00FF00FF)
                gfxRowTmp[x] = pix;
        }
        memcpy(gfx.front.ptr + cast(size_t)y * fstride + x0, gfxRowTmp.ptr, cast(size_t)cw * 4);
    }
}

// Bring the screen up to date. Cheap (a few comparisons) when nothing changed.
void gfxPresent() @nogc nothrow
{
    if (!gfx.ready)
        return;

    int mx = mouse.x, my = mouse.y;
    bool moved = !gfx.mouseDrawn || mx != gfx.mouseX || my != gfx.mouseY;
    if (!gfx.fullDirty && gfx.numDirty == 0 && !moved)
        return;

    if (gfx.fullDirty)
    {
        size_t total = cast(size_t)gfx.scene.height * gfx.scene.pitch;
        fastMemcpyNT(gfx.front.ptr, gfx.scene.ptr, total);
    }
    else
    {
        for (uint i = 0; i < gfx.numDirty; i++)
            gfxBlitRect(gfx.dirty[i].x0, gfx.dirty[i].y0, gfx.dirty[i].x1, gfx.dirty[i].y1);
        if (gfx.mouseDrawn && moved) // erase the old cursor
            gfxBlitRect(gfx.mouseX, gfx.mouseY, gfx.mouseX + CURSOR_WIDTH, gfx.mouseY + CURSOR_HEIGHT);
    }

    // Always redraw the cursor last: a dirty rectangle may have painted over it.
    gfxDrawCursor(mx, my);

    gfx.numDirty = 0;
    gfx.fullDirty = false;
    gfx.mouseDrawn = true;
    gfx.mouseX = mx;
    gfx.mouseY = my;
}

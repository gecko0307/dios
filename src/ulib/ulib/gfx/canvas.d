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

module ulib.gfx.canvas;

/**
 * A Canvas is a view of a rectangle of 32 bit pixels (0x00RRGGBB) in memory: a window's
 * drawable area, the server's back buffer, or a part of either (sub()). It does not own
 * the memory. All drawing is clipped to the canvas, so it is safe to draw outside of it.
 */

/// Packs 0..255 channels into a pixel.
uint rgb(uint r, uint g, uint b) @nogc nothrow
{
    return ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
}

struct Canvas
{
    uint* pixels; // top left pixel
    int width;
    int height;
    int stride; // distance between rows in PIXELS (the kernel reports bytes)

    /// Does it point at something drawable?
    bool valid() @nogc nothrow
    {
        return pixels !is null && width > 0 && height > 0;
    }

    // Clip x, y, w, h to the canvas. False if nothing is left.
    private bool clip(ref int x, ref int y, ref int w, ref int h) @nogc nothrow
    {
        if (x < 0) { w += x; x = 0; }
        if (y < 0) { h += y; y = 0; }
        if (x + w > width) w = width - x;
        if (y + h > height) h = height - y;
        return w > 0 && h > 0;
    }

    /// A canvas for a part of this one (clipped). Drawing on it changes this canvas' pixels.
    Canvas sub(int x, int y, int w, int h) @nogc nothrow
    {
        Canvas c;
        c.pixels = null;
        c.width = 0;
        c.height = 0;
        c.stride = 0;
        if (!valid() || !clip(x, y, w, h))
            return c;
        c.pixels = pixels + cast(size_t)y * cast(size_t)stride + cast(size_t)x;
        c.width = w;
        c.height = h;
        c.stride = stride;
        return c;
    }

    void setPixel(int x, int y, uint color) @nogc nothrow
    {
        if (x < 0 || y < 0 || x >= width || y >= height)
            return;
        pixels[cast(size_t)y * cast(size_t)stride + cast(size_t)x] = color;
    }

    /// The pixel at x, y; 0 outside the canvas.
    uint getPixel(int x, int y) @nogc nothrow
    {
        if (x < 0 || y < 0 || x >= width || y >= height)
            return 0;
        return pixels[cast(size_t)y * cast(size_t)stride + cast(size_t)x];
    }

    void fillRect(int x, int y, int w, int h, uint color) @nogc nothrow
    {
        if (!valid() || !clip(x, y, w, h))
            return;
        for (int row = 0; row < h; row++)
        {
            uint* p = pixels + cast(size_t)(y + row) * cast(size_t)stride + cast(size_t)x;
            for (int col = 0; col < w; col++)
                p[col] = color;
        }
    }

    void clear(uint color) @nogc nothrow
    {
        fillRect(0, 0, width, height, color);
    }

    void hline(int x, int y, int w, uint color) @nogc nothrow
    {
        fillRect(x, y, w, 1, color);
    }

    void vline(int x, int y, int h, uint color) @nogc nothrow
    {
        fillRect(x, y, 1, h, color);
    }

    /// Outline of a rectangle, 1 pixel wide, inside x, y, w, h.
    void rect(int x, int y, int w, int h, uint color) @nogc nothrow
    {
        if (w <= 0 || h <= 0)
            return;
        hline(x, y, w, color);
        hline(x, y + h - 1, w, color);
        vline(x, y, h, color);
        vline(x + w - 1, y, h, color);
    }

    /// Bresenham line from (x0, y0) to (x1, y1), both ends included.
    void line(int x0, int y0, int x1, int y1, uint color) @nogc nothrow
    {
        int dx = x1 > x0 ? x1 - x0 : x0 - x1;
        int dy = y1 > y0 ? y1 - y0 : y0 - y1;
        int sx = x0 < x1 ? 1 : -1;
        int sy = y0 < y1 ? 1 : -1;
        int err = dx - dy;
        for (;;)
        {
            setPixel(x0, y0, color);
            if (x0 == x1 && y0 == y1)
                break;
            int e2 = 2 * err;
            if (e2 > -dy)
            {
                err -= dy;
                x0 += sx;
            }
            if (e2 < dx)
            {
                err += dx;
                y0 += sy;
            }
        }
    }

    /// Copies the part sx, sy, w, h of `src` to dx, dy of this canvas (opaque, clipped on both sides).
    void blitRect(const(Canvas)* src, int sx, int sy, int w, int h, int dx, int dy) @nogc nothrow
    {
        if (!valid() || src.pixels is null)
            return;
        if (sx < 0) { dx -= sx; w += sx; sx = 0; }
        if (sy < 0) { dy -= sy; h += sy; sy = 0; }
        if (sx + w > src.width) w = src.width - sx;
        if (sy + h > src.height) h = src.height - sy;
        if (dx < 0) { sx -= dx; w += dx; dx = 0; }
        if (dy < 0) { sy -= dy; h += dy; dy = 0; }
        if (dx + w > width) w = width - dx;
        if (dy + h > height) h = height - dy;
        if (w <= 0 || h <= 0)
            return;
        for (int row = 0; row < h; row++)
        {
            const(uint)* s = src.pixels + cast(size_t)(sy + row) * cast(size_t)src.stride + cast(size_t)sx;
            uint* d = pixels + cast(size_t)(dy + row) * cast(size_t)stride + cast(size_t)dx;
            for (int col = 0; col < w; col++)
                d[col] = s[col];
        }
    }

    /// Copies all of `src` to dx, dy.
    void blit(const(Canvas)* src, int dx, int dy) @nogc nothrow
    {
        blitRect(src, 0, 0, src.width, src.height, dx, dy);
    }
}

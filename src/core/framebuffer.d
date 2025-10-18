module core.framebuffer;

struct Framebuffer
{
    uint* ptr;
    uint width;
    uint height;
    uint pitch;
    uint bytesPerPixel;
}

void fillScreen(
    Framebuffer* fb,
    uint color) @nogc nothrow
{
    for (uint y = 0; y < fb.height; y++)
    {
        for (uint x = 0; x < fb.width; x++)
        {
            uint offset = y * (fb.pitch / fb.bytesPerPixel) + x;
            fb.ptr[offset] = color;
        }
    }
}

void drawRect(
    Framebuffer* fb,
    uint x0, uint y0,
    uint color,
    ushort w, ushort h) @nogc nothrow
{
    for (uint y = 0; y < h; y++)
    {
        if (y0 + y >= fb.height)
            break;
        for (uint x = 0; x < w; x++)
        {
            if (x0 + x >= fb.width)
                break;
            uint offset = (y0 + y) * (fb.pitch / fb.bytesPerPixel) + (x0 + x);
            fb.ptr[offset] = color;
        }
    }
}

void drawBitmap(
    Framebuffer* fb,
    uint x0, uint y0,
    const uint[] bitmap,
    ushort w, ushort h) @nogc nothrow
{
    for (uint y = 0; y < h; y++)
    {
        if (y0 + y >= fb.height)
            break;
        for (uint x = 0; x < w; x++)
        {
            if (x0 + x >= fb.width)
                break;
            uint offset = (y0 + y) * (fb.pitch / fb.bytesPerPixel) + (x0 + x);
            uint pix = bitmap[y * w + x];
            if (pix != 0x00FF00FF)
                fb.ptr[offset] = bitmap[y * w + x];
        }
    }
}

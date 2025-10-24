module dios.core.framebuffer;

struct Framebuffer
{
    uint* ptr;
    uint width;
    uint height;
    uint pitch;
    uint bytesPerPixel;
}

extern(C):

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
    uint w, uint h) @nogc nothrow
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

void printChar(
    Framebuffer* fb,
    uint x0, uint y0,
    const uint[] bitmapFont,
    uint numCharsH,
    uint w, uint h,
    char c) @nogc nothrow
{
    uint bmpW = numCharsH * w;
    uint charX = w * (c % 16);
    uint charY = h * (c / 16);
    for (uint y = 0; y < h; y++)
    {
        if (y0 + y >= fb.height)
            break;
        for (uint x = 0; x < w; x++)
        {
            if (x0 + x >= fb.width)
                break;
            uint offset = (y0 + y) * (fb.pitch / fb.bytesPerPixel) + (x0 + x);
            uint pix = bitmapFont[(charY + y) * bmpW + (charX + x)];
            if (pix != 0x00FF00FF)
                fb.ptr[offset] = pix;
        }
    }
}

void printStr(
    Framebuffer* fb,
    uint x0, uint y0,
    const uint[] bitmapFont,
    uint numCharsH,
    uint w, uint h,
    const(char)[] str) @nogc nothrow
{
    uint x = x0;
    for (size_t i = 0; i < str.length; i++)
    {
        printChar(fb, x, y0, bitmapFont, numCharsH, w, h, str[i]);
        x += w - 2;
    }
}

void clearChar(Framebuffer* fb,
    uint x0, uint y0,
    uint w, uint h, uint color) @nogc nothrow
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

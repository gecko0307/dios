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
module wallpaper;

import ulib.gfx;
import config;

struct Wallpaper
{
    uint width;
    uint height;
    uint[] data;
}

private __gshared Wallpaper _wallpaper;

void wallpaperInit(ImageBGRA* img)
{
    _wallpaper.width = img.width;
    _wallpaper.height = img.height;
    _wallpaper.data = (cast(uint*)img.data.ptr)[0..img.data.length / uint.sizeof];
}

void wallpaperDraw(Canvas* canvas)
{
    if (_wallpaper.data.length == 0 ||
        _wallpaper.width == 0 ||
        _wallpaper.height == 0)
    {
        canvas.fillRect(0, 0, canvas.width, canvas.height, desktopColor);
        return;
    }

    uint dstWidth = canvas.width;
    uint dstHeight = canvas.height;

    float scaleX = cast(float)_wallpaper.width / dstWidth;
    float scaleY = cast(float)_wallpaper.height / dstHeight;

    for (uint y = 0; y < dstHeight; y++)
    {
        // Pixel-center mapping
        float srcY = (cast(float)y + 0.5f) * scaleY - 0.5f;

        int y0 = cast(int)srcY;
        float fy = srcY - y0;

        if (y0 < 0)
        {
            y0 = 0;
            fy = 0.0f;
        }

        int y1 = y0 + 1;

        if (y1 >= cast(int)_wallpaper.height)
        {
            y1 = cast(int)_wallpaper.height - 1;
            fy = 0.0f;
        }

        for (uint x = 0; x < dstWidth; x++)
        {
            float srcX = (cast(float)x + 0.5f) * scaleX - 0.5f;

            int x0 = cast(int)srcX;
            float fx = srcX - x0;

            if (x0 < 0)
            {
                x0 = 0;
                fx = 0.0f;
            }

            int x1 = x0 + 1;

            if (x1 >= cast(int)_wallpaper.width)
            {
                x1 = cast(int)_wallpaper.width - 1;
                fx = 0.0f;
            }

            uint c00 = _wallpaper.data[y0 * _wallpaper.width + x0];
            uint c10 = _wallpaper.data[y0 * _wallpaper.width + x1];
            uint c01 = _wallpaper.data[y1 * _wallpaper.width + x0];
            uint c11 = _wallpaper.data[y1 * _wallpaper.width + x1];

            float w00 = (1.0f - fx) * (1.0f - fy);
            float w10 = fx * (1.0f - fy);
            float w01 = (1.0f - fx) * fy;
            float w11 = fx * fy;

            uint b =
                cast(uint)(
                    (c00 & 0xFF) * w00 +
                    (c10 & 0xFF) * w10 +
                    (c01 & 0xFF) * w01 +
                    (c11 & 0xFF) * w11);

            uint g =
                cast(uint)(
                    ((c00 >> 8) & 0xFF) * w00 +
                    ((c10 >> 8) & 0xFF) * w10 +
                    ((c01 >> 8) & 0xFF) * w01 +
                    ((c11 >> 8) & 0xFF) * w11);

            uint r =
                cast(uint)(
                    ((c00 >> 16) & 0xFF) * w00 +
                    ((c10 >> 16) & 0xFF) * w10 +
                    ((c01 >> 16) & 0xFF) * w01 +
                    ((c11 >> 16) & 0xFF) * w11);

            uint a =
                cast(uint)(
                    ((c00 >> 24) & 0xFF) * w00 +
                    ((c10 >> 24) & 0xFF) * w10 +
                    ((c01 >> 24) & 0xFF) * w01 +
                    ((c11 >> 24) & 0xFF) * w11);

            canvas.setPixel(x, y, (a << 24) | (r << 16) | (g << 8) | b);
        }
    }
}

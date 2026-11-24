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
module ulib.gfx.image;

import ulib.gfx.canvas;

/**
 * Pixels are stored as 4 bytes per pixel in memory order B, G, R, A.
 * On a little-endian machine that is exactly a uint 0xAARRGGBB, which is what Canvas expects.
 */
struct ImageBGRA
{
    uint width;
    uint height;
    ubyte[] data;
}

extern(C):

void imageAsCanvas(ImageBGRA* img, Canvas* outCanvas) @nogc nothrow
{
    outCanvas.pixels = cast(uint*)img.data.ptr;
    outCanvas.width = img.width;
    outCanvas.height = img.height;
    outCanvas.stride = img.width;
}

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

module tgafile;

import ulib.dios;
import ulib.gfx;

/**
 * Reads and decodes a TGA file (24 or 32 bit) into `img`: pixels are 0xAARRGGBB with straight alpha,
 * 255 (opaque) for a file without an alpha channel. The pixels belong to the caller, who frees them
 * with ufree(img.data.ptr).
 *
 * Returns false if it fails. A file that does not exist is reported only if `reportMissing` is set:
 * for images that have a built-in replacement, no file is not an error.
 */
bool loadTGAFile(const(char)* path, ImageBGRA* img, bool reportMissing = true)
{
    UStat st;
    if (ustat(path, &st) != 0)
    {
        if (reportMissing)
            uprintf("Error: cannot open \"%s\"\n", path);
        return false;
    }

    size_t len = st.size;
    if (len < TGAHeader.sizeof)
    {
        uprintf("Error: \"%s\" is not a TGA file or corrupted\n", path);
        return false;
    }

    int file = uopen(path, O_RDONLY);
    if (file < 0)
    {
        uprintf("Error: cannot open \"%s\"\n", path);
        return false;
    }

    ubyte* buf = cast(ubyte*)umalloc(len);
    if (buf is null)
    {
        uclose(file);
        uprintf("Error: failed to allocate %d byte(s)\n", len);
        return false;
    }

    long bytesRead = ureadfull(file, buf, len);
    uclose(file);
    if (bytesRead != cast(long)len)
    {
        ufree(buf);
        uprintf("Error: failed to read \"%s\"\n", path);
        return false;
    }

    bool ok = loadTGA(buf[0..len], img);
    ufree(buf);
    if (!ok)
        uprintf("Error: failed to decode \"%s\"\n", path);
    return ok;
}

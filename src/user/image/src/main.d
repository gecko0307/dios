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
module main;

/*
 * DIOS image viewer.
 * Supports only TGA format at the moment (both raw RGB and RLE-compressed).
 */

import ulib.dios;
import ulib.gfx;

int main(string[] args)
{
    if (args.length == 0)
        return 0;
    
    string path = args[0];
    
    UStat st;
    if (ustat(path.ptr, &st) != 0)
    {
        uprintf("Error: cannot open \"%s\"\n", path.ptr);
        return 1;
    }
    
    size_t len = st.size;
    if (len < TGAHeader.sizeof)
    {
        uprintf("Error: \"%s\" is not a TGA file or corrupted\n", path.ptr);
        return 1;
    }
    
    int file = uopen(path.ptr, O_RDONLY);
    if (file < 0)
    {
        uprintf("Error: cannot open \"%s\"\n", path.ptr);
        return 1;
    }
    
    ubyte* buf = cast(ubyte*)umalloc(len);
    if (buf is null)
    {
        uprintf("Error: failed to allocate %d byte(s)\n", len);
        return 1;
    }
    
    scope(exit)
    {
        if (buf !is null)
            ufree(buf);
    }
    
    long bytesRead = uread(file, buf, len);
    if (bytesRead != cast(long)len)
    {
        uprintf("Error: failed to read \"%s\"\n", path.ptr);
        return 1;
    }
    
    uclose(file);
    
    ubyte[] input = buf[0..len];
    
    ImageBGRA img;
    scope(exit)
    {
        if (img.data.length > 0)
        {
            ufree(img.data.ptr);
            img.data = [];
        }
    }
    
    if (!loadTGA(input, &img))
    {
        uprintf("Error: failed to decode \"%s\"\n", path.ptr);
        return 1;
    }
    
    ufree(buf);
    buf = null;
    
    Canvas imgCanvas;
    imageAsCanvas(&img, &imgCanvas);
    
    Window window;
    bool running = true;
    
    if (!windowCreate(&window, img.width, img.height))
    {
        uprintf("Error: could not create a window\n");
        return 1;
    }

    if (!window.serverRunning)
        uprintf("Warning: no graphics server running\n");

    while(running)
    {
        GfxEvent event;
        bool got = windowPoll(&window, &event, 16);
        while(got)
        {
            if (event.type == GFX_EV_CLOSE)
                running = false;
            
            got = windowPoll(&window, &event, 0);
        }

        Canvas* c = &window.canvas;
        c.blit(&imgCanvas, 0, 0);
        
        windowCommit(&window);
    }

    windowClose(&window);
    
    return 0;
}

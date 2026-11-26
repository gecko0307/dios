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
 * DIOS Desktop Manager.
 * WIP.
 */

import ulib.dios;
import ulib.gfx;

__gshared GfxInfo gfxInfo;
__gshared uint taskbarHeight = 34;
__gshared uint taskbarColor = 0xFFEBEBEB;

int main(string[] args)
{
    ugfxInfo(&gfxInfo);
    
    Window taskbar;
    bool running = true;
    
    if (!windowCreateDesktop(&taskbar, gfxInfo.width, taskbarHeight, 0, gfxInfo.height - taskbarHeight))
    {
        uprintf("Error: could not create a taskbar window\n");
        return 1;
    }

    if (!taskbar.serverRunning)
        uprintf("Warning: no graphics server running\n");

    Canvas* canv = &taskbar.canvas;
    canv.fillRect(0, 0, gfxInfo.width, taskbarHeight, taskbarColor);

    while(running)
    {
        GfxEvent event;
        bool got = windowPoll(&taskbar, &event, 16);
        while(got)
        {
            if (event.type == GFX_EV_CLOSE)
                running = false;
            
            got = windowPoll(&taskbar, &event, 0);
        }

        //c.blit(&imgCanvas, 0, 0);
        
        windowCommit(&taskbar);
    }

    windowClose(&taskbar);
    
    return 0;
}

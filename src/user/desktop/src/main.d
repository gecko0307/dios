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
 * Work-in-progress.
 */

import ulib.dios;
import ulib.gfx;

__gshared uint taskbarIconsWidth;
__gshared uint taskbarIconsHeight;
__gshared uint[] taskbarIcons;

struct Icon
{
    uint x;
    uint y;
    uint width;
    uint height;
    uint[] data;
}

bool loadTaskbarIcons()
{
    string path = "/etc/desktop/taskbar-icons.tga";
    
    UStat st;
    if (ustat(path.ptr, &st) != 0)
    {
        uprintf("Error: cannot open \"%s\"\n", path.ptr);
        return false;
    }
    
    size_t len = st.size;
    if (len < TGAHeader.sizeof)
    {
        uprintf("Error: \"%s\" is not a TGA file or corrupted\n", path.ptr);
        return false;
    }
    
    int file = uopen(path.ptr, O_RDONLY);
    if (file < 0)
    {
        uprintf("Error: cannot open \"%s\"\n", path.ptr);
        return false;
    }
    
    ubyte* buf = cast(ubyte*)umalloc(len);
    if (buf is null)
    {
        uprintf("Error: failed to allocate %d byte(s)\n", len);
        return false;
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
        return false;
    }
    
    uclose(file);
    
    ubyte[] input = buf[0..len];
    
    ImageBGRA img;
    if (!loadTGA(input, &img))
    {
        uprintf("Error: failed to decode \"%s\"\n", path.ptr);
        return 1;
    }
    
    ufree(buf);
    buf = null;
    
    taskbarIconsWidth = img.width;
    taskbarIconsHeight = img.height;
    
    // TODO: array cast in object.d
    taskbarIcons = (cast(uint*)img.data.ptr)[0..img.data.length / uint.sizeof];
    
    return true;
}

bool getTaskbarIcon(Icon* icon)
{
    if (taskbarIcons.length == 0)
        return false;
    
    if (icon.width == 0 || icon.height == 0)
        return false;
    
    if (icon.x >= taskbarIconsWidth ||
        icon.y >= taskbarIconsHeight ||
        icon.width > taskbarIconsWidth ||
        icon.height > taskbarIconsHeight)
        return false;
    
    size_t size = icon.width * icon.height * 4;
    void* buf = umalloc(size);
    icon.data = (cast(uint*)buf)[0..size / uint.sizeof]; // TODO: array cast in object.d
    
    for (size_t y = 0; y < icon.height; y++)
    for (size_t x = 0; x < icon.width; x++)
    {
        icon.data[y * icon.width + x] = taskbarIcons[(icon.y + y) * taskbarIconsWidth + icon.x + x];
    }
    
    return true;
}

void drawIcon(Canvas* canvas, Icon* icon, uint x, uint y)
{
    for (int py = 0; py < icon.height; py++)
    for (int px = 0; px < icon.width; px++)
    {
        uint col = icon.data[py * icon.width + px];
        canvas.setPixel(x + px, py + y, col);
    }
}

void openTerminal()
{
    // TODO: make configurable
    int terminalId = uspawn("/bin/gterm.elf", "", STDOUT_INHERIT);
    if (terminalId == -1)
        uprintf("Warning: failed to run /bin/gterm.elf. GTerm is not installed\n");
}

__gshared GfxInfo gfxInfo;
__gshared uint taskbarHeight = 48;
__gshared uint taskbarColor = 0xFFEBEBEB;

int main(string[] args)
{
    ugfxInfo(&gfxInfo);
    
    bool taskbarIconsPresent = loadTaskbarIcons();
    if (!taskbarIconsPresent)
    {
        uprintf("Error: failed to load taskbar icons\n");
        return 1;
    }
    scope(exit)
    {
        if (taskbarIcons.length)
            ufree(taskbarIcons.ptr);
    }
    
    Window taskbar;
    bool running = true;
    
    uint taskbarY = gfxInfo.height - taskbarHeight;
    if (!windowCreateDesktop(&taskbar, gfxInfo.width, taskbarHeight, 0, taskbarY))
    {
        uprintf("Error: could not create a taskbar window\n");
        return 1;
    }

    if (!taskbar.serverRunning)
        uprintf("Warning: no graphics server running\n");

    Canvas* canv = &taskbar.canvas;
    canv.fillRect(0, 0, gfxInfo.width, taskbarHeight, taskbarColor);
    
    Icon terminalIcon;
    terminalIcon.x = 0;
    terminalIcon.y = 0;
    terminalIcon.width = 48;
    terminalIcon.height = 48;
    scope(exit)
    {
        if (terminalIcon.data.length)
            ufree(terminalIcon.data.ptr);
    }
    if (taskbarIconsPresent)
    {
        if (getTaskbarIcon(&terminalIcon))
        {
            drawIcon(canv, &terminalIcon, 0, 0);
        }
    }
    
    uint mouseX = 0;
    uint mouseY = 0;
    bool mouseDown = false;
    bool clicked = false;

    while(running)
    {
        clicked = false;
        
        GfxEvent event;
        bool got = windowPoll(&taskbar, &event, 16);
        while(got)
        {
            if (event.type == GFX_EV_CLOSE)
                running = false;
            else if (event.type == GFX_EV_MOUSE)
            {
                // event.a, event.b: position inside the window
                // event.c: buttons
                // event.d: wheel
                mouseX = event.a;
                mouseY = event.b;
                if ((event.c & GFX_BTN_LEFT) != 0)
                    mouseDown = true;
                else if (mouseDown)
                {
                    mouseDown = false;
                    clicked = true;
                }
            }
            
            got = windowPoll(&taskbar, &event, 0);
        }

        //c.blit(&imgCanvas, 0, 0);
        
        windowCommit(&taskbar);
        
        if (clicked)
        {
            if (mouseX > 0 && mouseX < terminalIcon.width &&
                mouseY > 0 && mouseY < terminalIcon.height)
                openTerminal();
        }
    }

    windowClose(&taskbar);
    
    return 0;
}

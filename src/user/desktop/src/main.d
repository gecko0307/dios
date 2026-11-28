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
import image;
import config;
import wallpaper;

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

void openBlackboard()
{
    // TODO: make configurable
    int blackboardId = uspawn("/bin/blackboard.elf", "", STDOUT_INHERIT);
    if (blackboardId == -1)
        uprintf("Warning: failed to run /bin/blackboard.elf. Blackboard is not installed\n");
}

__gshared GfxInfo gfxInfo;

int main(string[] args)
{
    if (utaskfind("desktop") != ugetpid())
    {
        uprintf("Desktop manager is already running");
        return 0;
    }
    
    ugfxInfo(&gfxInfo);
    
    ImageBGRA iconsImg;
    bool taskbarIconsPresent = loadImage("/etc/desktop/taskbar-icons.tga", &iconsImg);
    if (!taskbarIconsPresent)
    {
        return 1;
    }
    scope(exit)
    {
        if (iconsImg.data.length)
            ufree(iconsImg.data.ptr);
    }
    taskbarIconsWidth = iconsImg.width;
    taskbarIconsHeight = iconsImg.height;
    // TODO: array cast in object.d
    taskbarIcons = (cast(uint*)iconsImg.data.ptr)[0..iconsImg.data.length / uint.sizeof];
    
    ImageBGRA wallpaperImg;
    bool wallpaperPresent = loadImage("/etc/desktop/wallpaper.tga", &wallpaperImg);
    scope(exit)
    {
        if (wallpaperImg.data.length)
            ufree(wallpaperImg.data.ptr);
    }
    if (wallpaperPresent)
        wallpaperInit(&wallpaperImg);
    
    Window desktop;
    if (!windowCreateDesktop(&desktop, gfxInfo.width, gfxInfo.height, 0, 0))
    {
        uprintf("Error: could not create a desktop window\n");
        return 1;
    }

    if (!desktop.serverRunning)
        uprintf("Warning: no graphics server running\n");

    Canvas* canv = &desktop.canvas;
    
    // Draw desktop background
    wallpaperDraw(canv);

    // Draw taskbar
    uint taskbarY = canv.height - taskbarHeight;
    canv.fillRect(0, taskbarY, canv.width, taskbarHeight, taskbarColor);
    
    Icon terminalIcon;
    terminalIcon.x = 0;
    terminalIcon.y = 0;
    terminalIcon.width = iconSize;
    terminalIcon.height = iconSize;
    scope(exit)
    {
        if (terminalIcon.data.length)
            ufree(terminalIcon.data.ptr);
    }
    if (taskbarIconsPresent)
    {
        if (getTaskbarIcon(&terminalIcon))
        {
            drawIcon(canv, &terminalIcon, 0, taskbarY);
        }
    }
    
    Icon blackboardIcon;
    blackboardIcon.x = iconSize;
    blackboardIcon.y = 0;
    blackboardIcon.width = iconSize;
    blackboardIcon.height = iconSize;
    scope(exit)
    {
        if (blackboardIcon.data.length)
            ufree(blackboardIcon.data.ptr);
    }
    if (taskbarIconsPresent)
    {
        if (getTaskbarIcon(&blackboardIcon))
        {
            drawIcon(canv, &blackboardIcon, iconSize, taskbarY);
        }
    }
    
    // TODO: make configurable
    int imageViewerId = uspawn("/bin/image.elf", "/etc/desktop/splash.tga", STDOUT_INHERIT);
    if (imageViewerId == -1)
        uprintf("gfxd: failed to run /bin/image.elf. Image Viewer is not installed\n");
    
    bool running = true;
    
    uint mouseX = 0;
    uint mouseY = 0;
    bool mouseDown = false;
    bool clicked = false;

    while(running)
    {
        clicked = false;
        
        GfxEvent event;
        bool got = windowPoll(&desktop, &event, 16);
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
            
            got = windowPoll(&desktop, &event, 0);
        }
        
        windowCommit(&desktop);
        
        if (clicked)
        {
            if (mouseX > 0 && mouseX < iconSize &&
                mouseY > taskbarY && mouseY < taskbarY + iconSize)
                openTerminal();
            else if (mouseX > iconSize && mouseX < iconSize + iconSize &&
                mouseY > taskbarY && mouseY < taskbarY + iconSize)
                openBlackboard();
        }
    }

    windowClose(&desktop);
    
    return 0;
}

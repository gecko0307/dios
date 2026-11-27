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

__gshared uint wallpaperWidth;
__gshared uint wallpaperHeight;
__gshared uint[] wallpaper;

struct Icon
{
    uint x;
    uint y;
    uint width;
    uint height;
    uint[] data;
}

bool loadImage(string path, ImageBGRA* img)
{
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
    
    long bytesRead = ureadfull(file, buf, len);
    if (bytesRead != cast(long)len)
    {
        uprintf("Error: failed to read \"%s\", got %d bytes instead of %d\n", path.ptr, bytesRead, len);
        return false;
    }
    
    uclose(file);
    
    ubyte[] input = buf[0..len];
    
    if (!loadTGA(input, img))
    {
        uprintf("Error: failed to decode \"%s\"\n", path.ptr);
        return 1;
    }
    
    ufree(buf);
    buf = null;
    
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

void drawWallpaper(Canvas* canvas)
{
    if (wallpaper.length == 0 ||
        wallpaperWidth == 0 ||
        wallpaperHeight == 0)
    {
        canvas.fillRect(0, 0, canvas.width, canvas.height, desktopColor);
        return;
    }

    uint dstWidth = canvas.width;
    uint dstHeight = canvas.height;

    float scaleX = cast(float)wallpaperWidth / dstWidth;
    float scaleY = cast(float)wallpaperHeight / dstHeight;

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

        if (y1 >= cast(int)wallpaperHeight)
        {
            y1 = cast(int)wallpaperHeight - 1;
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

            if (x1 >= cast(int)wallpaperWidth)
            {
                x1 = cast(int)wallpaperWidth - 1;
                fx = 0.0f;
            }

            uint c00 = wallpaper[y0 * wallpaperWidth + x0];
            uint c10 = wallpaper[y0 * wallpaperWidth + x1];
            uint c01 = wallpaper[y1 * wallpaperWidth + x0];
            uint c11 = wallpaper[y1 * wallpaperWidth + x1];

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

enum uint iconSize = 48;

__gshared GfxInfo gfxInfo;

__gshared uint taskbarHeight = 48;

__gshared uint desktopColor = 0x00203A5A;
__gshared uint taskbarColor = 0x00EBEBEB;

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
    {
        wallpaperWidth = wallpaperImg.width;
        wallpaperHeight = wallpaperImg.height;
        // TODO: array cast in object.d
        wallpaper = (cast(uint*)wallpaperImg.data.ptr)[0..wallpaperImg.data.length / uint.sizeof];
    }
    
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
    drawWallpaper(canv);

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

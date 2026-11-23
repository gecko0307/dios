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

/**
 * gfxdemo - template for a graphical program.
 *
 *   1. windowCreate()   gives you a drawable area (win.canvas) of the size you ask for
 *   2. draw into it     win.canvas.fillRect(), line(), blit(), setPixel()... or write the
 *                       pixels yourself: win.canvas.pixels[y * win.canvas.stride + x] = 0x00RRGGBB
 *   3. windowCommit()   tells the graphics server that something changed
 *   4. windowPoll()     input and other events: mouse (relative to the window), keys, focus, close
 *
 * Run it from the shell: `run gfxdemo &`. It also works before the graphics server is
 * started (`gfx start`): the server picks it up when it comes.
 *
 * The program implements painting with the left mouse button.
 * Right button and C key clear the canvas, press Q or Escape to quit.
 */

import ulib.dios;
import ulib.gfx;

enum uint WIDTH = 320;
enum uint HEIGHT = 240;
enum uint PAPER = 0x00101820;

struct Demo
{
    Window win;
    Canvas paint; // what was painted: ordinary memory, composed into the window every frame
    int mouseX, mouseY;
    bool leftDown;
    int lastX, lastY;
    bool needRedraw = true;
    bool focused;
    bool running;

    void handle(const(GfxEvent)* event) @nogc nothrow
    {
        switch(event.type)
        {
            case GFX_EV_MOUSE:
                // event.a, event.b: position inside the window
                // event.c: buttons
                // event.d: wheel
                mouseX = event.a;
                mouseY = event.b;
                if ((event.c & GFX_BTN_LEFT) != 0)
                {
                    if (leftDown)
                        paint.line(lastX, lastY, mouseX, mouseY, rgb(120, 220, 120));
                    else
                        paint.setPixel(mouseX, mouseY, rgb(120, 220, 120));
                    leftDown = true;
                    lastX = mouseX;
                    lastY = mouseY;
                    needRedraw = true;
                }
                else
                    leftDown = false;
                if ((event.c & GFX_BTN_RIGHT) != 0)
                {
                    paint.clear(PAPER);
                    needRedraw = true;
                }
                break;

            case GFX_EV_KEY:
                // event.b: the ASCII character (0 if the key has none)
                // event.a: the scancode
                if (event.b == 'q' || event.b == 27)
                    running = false;
                else if (event.b == 'c')
                {
                    paint.clear(PAPER);
                    needRedraw = true;
                }
                break;

            case GFX_EV_FOCUS:
                focused = event.a != 0;
                break;

            case GFX_EV_CLOSE:
                running = false;
                break;

            default:
                break;
        }
    }

    void update() @nogc nothrow
    {
        
    }

    void draw() @nogc nothrow
    {
        if (!needRedraw)
            return;
        
        Canvas* c = &win.canvas;
        c.blit(&paint, 0, 0);
        //c.hline(mouseX - 6, mouseY, 13, rgb(255, 255, 255));
        //c.vline(mouseX, mouseY - 6, 13, rgb(255, 255, 255));
        c.rect(0, 0, c.width, c.height, focused ? rgb(255, 200, 40) : rgb(90, 90, 90));
        
        needRedraw = false;
    }
}

int main(string[] args)
{
    Demo d;
    d.running = true;

    if (!windowCreate(&d.win, WIDTH, HEIGHT))
    {
        uputs("gfxdemo: could not create a window\n");
        return 1;
    }
    
    d.paint.pixels = cast(uint*)umalloc(cast(size_t)WIDTH * HEIGHT * 4);
    if (d.paint.pixels is null)
    {
        windowClose(&d.win);
        return 1;
    }
    
    d.paint.width = cast(int)WIDTH;
    d.paint.height = cast(int)HEIGHT;
    d.paint.stride = cast(int)WIDTH;
    d.paint.clear(PAPER);

    if (!d.win.serverRunning)
        uputs("gfxdemo: no graphics server yet - 'gfx start' shows this window\n");

    while(d.running)
    {
        // The poll doubles as the frame timer: it returns after 16 ms at the latest
        GfxEvent event;
        bool got = windowPoll(&d.win, &event, 16);
        while(got)
        {
            d.handle(&event);
            got = windowPoll(&d.win, &event, 0);
        }

        d.update();
        d.draw();
        windowCommit(&d.win);
    }

    windowClose(&d.win);
    ufree(d.paint.pixels);
    return 0;
}

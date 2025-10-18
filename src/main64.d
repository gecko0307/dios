module main64;

import bootloader.limine;
import core.port;
import core.ps2;
import core.keyboard;
import core.pit;
import core.framebuffer;
import logo;
import cursor;
import font;
import console;
import stdio;
import error;

extern(C):

void kmain() @nogc nothrow
{
    ulong memBaseAddr = 0;
    auto memmap = memmapRequest.response;
    for (ulong i = 0; i < memmap.entry_count; i++)
    {
        auto entry = memmap.entries[i];
        if (entry.type == 0x1) // 0x1 == USABLE
        {
            memBaseAddr = entry.base;
            break;
        }
    }
    
    if (memBaseAddr == 0)
        hcf();
    
    auto resp = framebufferRequest.response;
    while (resp is null || resp.framebuffer_count < 1)
    {
        asm @nogc nothrow { hlt; }
        resp = framebufferRequest.response;
    }
    
    auto fb = resp.framebuffers[0];
    
    if (fb.bpp != 32)
        hcf();
    
    ulong numPixels = fb.height * fb.width;
    ulong framebufferSize = fb.height * fb.pitch;
    
    ulong backBufferAddr = memBaseAddr + 1024 * 1024; // leave 1 Mb
    ulong consoleBufferAddr = backBufferAddr + framebufferSize;
    
    Framebuffer frontBuffer;
    frontBuffer.ptr = cast(uint*)fb.address;
    frontBuffer.width = cast(uint)fb.width;
    frontBuffer.height = cast(uint)fb.height;
    frontBuffer.pitch = cast(uint)fb.pitch;
    frontBuffer.bytesPerPixel = cast(uint)fb.bpp / 8;
    
    Framebuffer backBuffer;
    backBuffer.ptr = cast(uint*)backBufferAddr;
    backBuffer.width = cast(uint)fb.width;
    backBuffer.height = cast(uint)fb.height;
    backBuffer.pitch = cast(uint)fb.pitch;
    backBuffer.bytesPerPixel = cast(uint)fb.bpp / 8;
    
    Framebuffer consoleBuffer;
    consoleBuffer.ptr = cast(uint*)consoleBufferAddr;
    consoleBuffer.width = cast(uint)fb.width;
    consoleBuffer.height = cast(uint)fb.height;
    consoleBuffer.pitch = cast(uint)fb.pitch;
    consoleBuffer.bytesPerPixel = cast(uint)fb.bpp / 8;
    
    ConsoleState* consoleState = consoleInit(&consoleBuffer, 16, 64);
    uint consoleCursorBlinkTimer = 0;
    bool consoleCursorVisible = true;
    
    PS2State* ps2State = ps2Init(cast(uint)fb.width - 1, cast(uint)fb.height - 1);
    
    uint time1 = pitTimeTicks();
    uint renderTimer = 0;
    
    uint clearColor = 0x000000AA;
    
    for (uint i = 0; i < numPixels; i++)
        frontBuffer.ptr[i] = clearColor;

    for (uint i = 0; i < numPixels; i++)
        backBuffer.ptr[i] = clearColor;
    
    for (uint i = 0; i < numPixels; i++)
        consoleBuffer.ptr[i] = clearColor;
    
    drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
    
    // Print info
    kprintf("DIOS 0.0.2\n");
    kprintf("---------------\n");
    kprintf("test %u\n", 100);
    
    while(1)
    {
        uint time2 = pitTimeTicks();
        uint delta = time2 - time1;
        time1 = time2;
        uint deltaMicroSec = (delta * 1000000) / PIT_FREQUENCY;
        renderTimer += deltaMicroSec;
        consoleCursorBlinkTimer += deltaMicroSec;
        
        ps2Poll();
        
        if (ps2State.keyPressed)
        {
            ps2State.keyPressed = 0;
            if (ps2State.lastScancode == 0x0e)
                consoleBack();
            else if (ps2State.lastScancode == 0x1C)
                consoleNewline();
            else
            {
                char c = scancodeToChar(ps2State.lastScancode);
                if (c)
                    consolePrintChar(c);
            }
        }
        
        if (consoleCursorBlinkTimer >= 100000)
        {
            consoleCursorVisible = !consoleCursorVisible;
            consoleCursorBlinkTimer = 0;
        }
        
        if (renderTimer >= 16666) // 16.7 millisecs
        {
            // Render
            fillScreen(&backBuffer, 0x000000AA);
            drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
            consoleBlitTo(&backBuffer);
            if (consoleCursorVisible)
            {
                drawRect(&backBuffer,
                    consoleState.x + consoleState.print_x + 2,
                    consoleState.y + consoleState.print_y + consoleState.v_stride - 6,
                    0x00FFFFFF,
                    consoleState.h_stride, 3);
            }
            
            drawBitmap(&backBuffer, ps2State.mx, ps2State.my, CURSOR, CURSOR_WIDTH, CURSOR_HEIGHT);
            
            for (uint i = 0; i < numPixels; i++)
            {
                frontBuffer.ptr[i] = backBuffer.ptr[i];
            }
            renderTimer = 0;
        }
    }
}

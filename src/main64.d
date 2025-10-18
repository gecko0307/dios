module main64;

import bootloader.limine;
import core.port;
import core.ps2;
import core.pit;
import core.framebuffer;
import logo;
import cursor;

extern(C):

// Halt and catch fire
void hcf() @nogc nothrow
{
    for (;;) asm @nogc nothrow
    {
        hlt;
    }
}

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
    
    ulong backBufferAddr = memBaseAddr + 1024 * 1024; // leave 1 Mb
    
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
    
    ulong numPixels = fb.height * fb.width;
    ulong framebufferSize = fb.height * fb.pitch;
    
    PS2MouseState* mouseState = ps2MouseInit(cast(uint)fb.width - 1, cast(uint)fb.height - 1);
    
    fillScreen(&frontBuffer, 0x000000AA);
    
    uint time1 = pitTimeTicks();
    uint renderTimer = 0;
    uint mouseTimer = 0;
    uint drawX = 0;
    uint drawY = 64;
    
    while(1)
    {
        uint time2 = pitTimeTicks();
        uint delta = time2 - time1;
        time1 = time2;
        uint deltaMs = (delta * 1000000) / PIT_FREQUENCY; // microseconds
        renderTimer += deltaMs;
        mouseTimer += deltaMs;
        
        if (mouseTimer >= 1000) // 1 millisec
        {
            ps2MousePoll();
            mouseTimer = 0;
        }
        
        if (renderTimer >= 16666) // 16.7 millisecs
        {
            // Render
            fillScreen(&backBuffer, 0x000000AA);
            drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
            
            // Draw moving rectangle
            if (drawX < backBuffer.width - 1)
                drawX++;
            else
                drawX = 0;
            drawRect(&backBuffer, drawX, drawY, 0x00FFFFFF, 32, 32);
            
            drawBitmap(&backBuffer, mouseState.x, mouseState.y, CURSOR, CURSOR_WIDTH, CURSOR_HEIGHT);
            
            for (uint i = 0; i < numPixels; i++)
            {
                frontBuffer.ptr[i] = backBuffer.ptr[i];
            }
            renderTimer = 0;
        }
    }
}

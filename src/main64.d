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
    
    uint consoleBufferX0 = 16;
    uint consoleBufferY0 = 64;
    uint consoleBufferW = cast(uint)fb.width - 32;
    uint consoleBufferH = CHAR_HEIGHT;
    uint printX = 0;
    uint printY = 0;
    
    PS2State* ps2State = ps2Init(cast(uint)fb.width - 1, cast(uint)fb.height - 1);
    
    uint time1 = pitTimeTicks();
    uint renderTimer = 0;
    uint inputTimer = 0;
    
    uint clearColor = 0x000000AA;
    
    for (uint i = 0; i < numPixels; i++)
        frontBuffer.ptr[i] = clearColor;

    for (uint i = 0; i < numPixels; i++)
        backBuffer.ptr[i] = clearColor;
    
    for (uint i = 0; i < numPixels; i++)
        consoleBuffer.ptr[i] = clearColor;
    
    drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
    
    printStr(&consoleBuffer, consoleBufferX0 + printX, consoleBufferY0 + printY, FONT, 16, CHAR_WIDTH, CHAR_HEIGHT, "Hello, World!");
    printY += CHAR_HEIGHT;
    consoleBufferH += CHAR_HEIGHT;
    
    while(1)
    {
        uint time2 = pitTimeTicks();
        uint delta = time2 - time1;
        time1 = time2;
        uint deltaMs = (delta * 1000000) / PIT_FREQUENCY; // microseconds
        renderTimer += deltaMs;
        inputTimer += deltaMs;
        
        if (inputTimer >= 1000) // 1 millisec
        {
            ps2Poll();
            inputTimer = 0;
        }
        
        if (ps2State.keyPressed)
        {
            ps2State.keyPressed = 0;
            if (ps2State.lastScancode == 0x0e)
            {
                if (printX > 0)
                {
                    printX -= CHAR_WIDTH - 2;
                    clearChar(&consoleBuffer, consoleBufferX0 + printX, consoleBufferY0 + printY, CHAR_WIDTH, CHAR_HEIGHT, clearColor);
                }
            }
            else
            {
                char c = scancodeToChar(ps2State.lastScancode);
                if (c)
                {
                    printChar(&consoleBuffer, consoleBufferX0 + printX, consoleBufferY0 + printY, FONT, 16, CHAR_WIDTH, CHAR_HEIGHT, c);
                    printX += CHAR_WIDTH - 2;
                    if (printX >= consoleBuffer.width - 16)
                    {
                        printX = 0;
                        printY += CHAR_HEIGHT;
                        consoleBufferH += CHAR_HEIGHT;
                    }
                }
            }
        }
        
        if (renderTimer >= 16666) // 16.7 millisecs
        {
            // Render
            fillScreen(&backBuffer, 0x000000AA);
            drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
            
            // Blit consoleBuffer to backBuffer
            for (uint y = 0; y < consoleBufferH; y++)
            {
                if (consoleBufferY0 + y >= backBuffer.height)
                    break;
                for (uint x = 0; x < consoleBufferW; x++)
                {
                    if (consoleBufferX0 + x >= backBuffer.width)
                        break;
                    uint offset = (consoleBufferY0 + y) * (backBuffer.pitch / backBuffer.bytesPerPixel) + (consoleBufferX0 + x);
                    backBuffer.ptr[offset] = consoleBuffer.ptr[offset];
                }
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

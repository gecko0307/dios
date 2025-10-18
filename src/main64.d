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
    
    uint printX = 16;
    uint printY = 64;
    
    PS2State* ps2State = ps2Init(cast(uint)fb.width - 1, cast(uint)fb.height - 1);
    
    uint time1 = pitTimeTicks();
    uint renderTimer = 0;
    uint inputTimer = 0;
    uint drawX = 0;
    uint drawY = 64;
    
    uint clearColor = 0x000000AA;
    
    for (uint i = 0; i < numPixels; i++)
    {
        frontBuffer.ptr[i] = clearColor;
    }
    
    for (uint i = 0; i < numPixels; i++)
    {
        backBuffer.ptr[i] = clearColor;
    }
    
    drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
    
    printStr(&backBuffer, printX, printY, FONT, 16, CHAR_WIDTH, CHAR_HEIGHT, "Hello, World!");
    printY += CHAR_HEIGHT;
    
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
                if (printX > 16)
                {
                    printX -= CHAR_WIDTH - 2;
                    clearChar(&backBuffer, printX, printY, CHAR_WIDTH, CHAR_HEIGHT, clearColor);
                }
            }
            else
            {
                char c = scancodeToChar(ps2State.lastScancode);
                if (c)
                {
                    printChar(&backBuffer, printX, printY, FONT, 16, CHAR_WIDTH, CHAR_HEIGHT, c);
                    printX += CHAR_WIDTH - 2;
                    if (printX >= backBuffer.width - 16)
                    {
                        printX = 16;
                        printY += CHAR_HEIGHT;
                    }
                }
            }
        }
        
        if (renderTimer >= 16666) // 16.7 millisecs
        {
            // Render
            /*
            fillScreen(&backBuffer, 0x000000AA);
            drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
            drawBitmap(&backBuffer, 16, 64, FONT, FONT_ATLAS_WIDTH, FONT_ATLAS_HEIGHT);
            
            // Draw moving rectangle
            if (drawX < backBuffer.width - 1)
                drawX++;
            else
                drawX = 0;
            drawRect(&backBuffer, drawX, drawY, 0x00FFFFFF, 32, 32);
            
            //drawBitmap(&backBuffer, ps2State.mx, ps2State.my, CURSOR, CURSOR_WIDTH, CURSOR_HEIGHT);
            */
            
            for (uint i = 0; i < numPixels; i++)
            {
                frontBuffer.ptr[i] = backBuffer.ptr[i];
            }
            renderTimer = 0;
        }
    }
}

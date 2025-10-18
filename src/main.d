module main;

import bootloader.multiboot;
import core.port;
import core.gdt;
import core.vga;
import core.keyboard;
import core.ps2;
import core.vbe;
import core.framebuffer;
import core.pit;
import logo;
import cursor;
import font;
import console;
import stdio;
import error;

extern(C):

__gshared string MemAvailable = "Available";
__gshared string MemReserved = "Reserved";

void kmain(uint magic, uint addr) @nogc nothrow
{
    initGDT();
    VGAConsole.init();
    
    byte status = kPortReadByte(0x64);
    if (status == 0x02)
        kPanic("Problem with GDT/CS!");
    
    if (magic != MULTIBOOT_BOOTLOADER_MAGIC)
        kPanic("Invalid Multiboot magic number");

    multiboot_info* mbi = cast(multiboot_info*)addr;

    uint lowerMemory = mbi.mem_lower; // between 0 and 640KB
    uint upperMemory = mbi.mem_upper; // from 1MB
    uint totalMemory = (1024 + mbi.mem_upper) / 1024 + 1;

    uint upperMemAdr = 0;
    uint upperMemLen = 0;

    if (checkFlag(mbi.flags, 6))
    {
        multiboot_memory_map_t* mmap = cast(multiboot_memory_map_t*)(mbi.mmap_addr);
        for (mmap = cast(multiboot_memory_map_t*) mbi.mmap_addr;
             cast(ulong)mmap < mbi.mmap_addr + mbi.mmap_length;
             mmap = cast(multiboot_memory_map_t*)(cast(ulong)mmap + mmap.size + mmap.size.sizeof))
        {
            if ((mmap.type == 1) && (mmap.length_low > upperMemLen))
            {
                upperMemAdr = mmap.addr_low;
                upperMemLen = mmap.length_low;
            }
        }
    }

    vbeInfo* vbe;
    if ((mbi.flags & MULTIBOOT_INFO_VIDEO_INFO) != 0)
        vbe = cast(vbeInfo*)mbi.vbe_mode_info;
    else
        kPanic("No framebuffer info!");
    
    uint numPixels = vbe.height * vbe.width;
    uint framebufferSize = vbe.height * vbe.pitch;
    
    uint backBufferAddr = upperMemAdr + 1024 * 1024; // leave 1 Mb
    uint consoleBufferAddr = backBufferAddr + framebufferSize;
    
    Framebuffer frontBuffer;
    frontBuffer.ptr = cast(uint*)vbe.framebuffer;
    frontBuffer.width = vbe.width;
    frontBuffer.height = vbe.height;
    frontBuffer.pitch = vbe.pitch;
    frontBuffer.bytesPerPixel = vbe.bpp / 8;
    
    Framebuffer backBuffer;
    backBuffer.ptr = cast(uint*)backBufferAddr;
    backBuffer.width = vbe.width;
    backBuffer.height = vbe.height;
    backBuffer.pitch = vbe.pitch;
    backBuffer.bytesPerPixel = vbe.bpp / 8;
    
    Framebuffer consoleBuffer;
    consoleBuffer.ptr = cast(uint*)consoleBufferAddr;
    consoleBuffer.width = vbe.width;
    consoleBuffer.height = vbe.height;
    consoleBuffer.pitch = vbe.pitch;
    consoleBuffer.bytesPerPixel = vbe.bpp / 8;
    
    ConsoleState* consoleState = consoleInit(&consoleBuffer, 16, 64);
    uint consoleCursorBlinkTimer = 0;
    bool consoleCursorVisible = true;
    
    PS2State* ps2State = ps2Init(cast(uint)vbe.width - 1, cast(uint)vbe.height - 1);
    
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
    kprintf("Multiboot magic: %x\n", magic);
    kprintf("Multiboot info:\n");
    if (checkFlag(mbi.flags, 2))
        kprintf("Arguments: %s\n", cast(char*)mbi.cmdline);
    kprintf("Boot loader: %s\n", cast(char*)mbi.boot_loader_name);
    kprintf("RAM: %u MB\n", totalMemory);
    kprintf("Memory map:\n");
    uint mmapEntryNum = 0;
    if (checkFlag(mbi.flags, 6))
    {
        multiboot_memory_map_t* mmap = cast(multiboot_memory_map_t*)(mbi.mmap_addr);
        for (mmap = cast(multiboot_memory_map_t*)mbi.mmap_addr;
             cast(ulong)mmap < mbi.mmap_addr + mbi.mmap_length;
             mmap = cast(multiboot_memory_map_t*)(cast(ulong)mmap + mmap.size + mmap.size.sizeof))
        {
            kprintf("Entry %u: ", mmapEntryNum);
            kprintf("address: %x, ", mmap.addr_low);
            if (mmap.length_low >= 1024 * 1024)
                kprintf("length: %u MB, ", (mmap.length_low / 1024) / 1024);
            else if (mmap.length_low >= 1024)
                kprintf("length: %u KB, ", mmap.length_low / 1024);
            else
                kprintf("length: %u B, ", mmap.length_low);
            kprintf("type: %s\n", (mmap.type == 1)? cast(char*)MemAvailable : cast(char*)MemReserved);
            mmapEntryNum++;
        }
    }
    kprintf("VBE framebuffer: %ux%u %ubpp\n", vbe.width, vbe.height, vbe.bpp);
    
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

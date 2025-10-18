module main;

import bootloader.multiboot;
import core.stdio;
import core.error;
import core.port;
import core.gdt;
import core.vga;
import core.console;
import core.stdarg;
import core.keyboard;
import core.ps2;
import core.vbe;
import core.framebuffer;
import core.pit;
import logo;
import cursor;

extern(C):

__gshared string MemAvailable = "Available";
__gshared string MemReserved = "Reserved";

void kmain(uint magic, uint addr) @nogc nothrow
{
    initGDT();
    Console.init();
    
    byte status = kPortReadByte(0x64);
    if (status == 0x02) {
        kPanic("Problem with GDT/CS!");
    }

    kprintf("DIOS 0.0.2\n");
    kprintf("---------------\n");
    kprintf("Multiboot magic: %x\n", magic);
    
    if (magic != MULTIBOOT_BOOTLOADER_MAGIC)
    {
        kPanic("Invalid Multiboot magic number");
    }

    multiboot_info* mbi = cast(multiboot_info*)addr;
    
    kprintf("Multiboot info:\n");

    if (checkFlag(mbi.flags, 2))
        kprintf("Arguments: %s\n", cast(char*)mbi.cmdline);

    kprintf("Boot loader: %s\n", cast(char*)mbi.boot_loader_name);

    kprintf("Memory:\n");
    uint lowerMemory = mbi.mem_lower; // between 0 and 640KB
    uint upperMemory = mbi.mem_upper; // from 1MB
    uint totalMemory = (1024 + mbi.mem_upper) / 1024 + 1;
    kprintf("Total memory: %u MB\n", totalMemory);

    uint upperMemAdr = 0;
    uint upperMemLen = 0;

    kprintf("Memory map:\n");
    uint entryNum = 0;
    if (checkFlag(mbi.flags, 6))
    {
        multiboot_memory_map_t* mmap = cast(multiboot_memory_map_t*)(mbi.mmap_addr);

        for (mmap = cast(multiboot_memory_map_t*) mbi.mmap_addr;
             cast(ulong)mmap < mbi.mmap_addr + mbi.mmap_length;
             mmap = cast(multiboot_memory_map_t*)(cast(ulong)mmap + mmap.size + mmap.size.sizeof))
        {
            kprintf(" Entry %u: ", entryNum);

            kprintf("address: %x, ", mmap.addr_low);

            if (mmap.length_low >= 1024 * 1024)
                kprintf("length: %u MB, ", (mmap.length_low / 1024) / 1024);
            else if (mmap.length_low >= 1024)
                kprintf("length: %u KB, ", mmap.length_low / 1024);
            else
                kprintf("length: %u B, ", mmap.length_low);

            kprintf("type: %s\n", (mmap.type == 1)? cast(char*)MemAvailable : cast(char*)MemReserved);

            if ((mmap.type == 1) && (mmap.length_low > upperMemLen))
            {
                upperMemAdr = mmap.addr_low;
                upperMemLen = mmap.length_low;
            }

            entryNum++;
        }
    }

    kprintf("Available memory:\n");
    kprintf(" address: %x\n", upperMemAdr);
    if (upperMemLen >= 1024 * 1024)
        kprintf(" length: %u MB\n", (upperMemLen / 1024) / 1024);
    else if (upperMemLen >= 1024)
        kprintf(" length: %u KB\n", upperMemLen / 1024);
    else
        kprintf(" length: %u B\n", upperMemLen);

    vbeInfo* vbe;
    kprintf("Video:\n");
    if ((mbi.flags & MULTIBOOT_INFO_VIDEO_INFO) != 0)
    {
        kprintf(" vbe_mode_info: %x\n", mbi.vbe_mode_info);
        kprintf(" vbe_mode: %u\n", mbi.vbe_mode);
        vbe = cast(vbeInfo*)mbi.vbe_mode_info;
    }
    else
    {
        kprintf(" No framebuffer info!\n");
        while(1)
        {}
    }
    
    uint backBufferAddr = upperMemAdr + 1024 * 1024; // leave 1 Mb
    
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
    
    uint numPixels = vbe.height * vbe.width;
    uint framebufferSize = vbe.height * vbe.pitch;
    
    fillScreen(&frontBuffer, 0x000000AA);
    
    kKbdEnable();
    kKbdFlushBuffer();
    
    PS2MouseState* mouseState = ps2MouseInit(cast(uint)vbe.width - 1, cast(uint)vbe.height - 1);
    
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
            drawBitmap(&backBuffer, mouseState.x, mouseState.y, CURSOR, CURSOR_WIDTH, CURSOR_HEIGHT);
            
            for (uint i = 0; i < numPixels; i++)
            {
                frontBuffer.ptr[i] = backBuffer.ptr[i];
            }
            renderTimer = 0;
        }
        
        /*
        while ((kPortReadByte(0x64) & 1) == 0)
        { }
        ubyte code = kPortReadByte(0x60);
        if (code == 0x0e)
        {
            VGAText.back();
        }
        else
        {
            char c = scancodeToChar(code);
            if (c)
            {
                VGAText.putChar(c);
            }
        }
        */
    }
}

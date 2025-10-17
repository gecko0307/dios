module main;

import core.stdio;
import core.error;
import core.multiboot;
import core.port;
import core.gdt;
import core.vga;
import core.console;
import core.stdarg;
import core.keyboard;
import core.vbe;
import logo;
import cursor;

extern(C):

__gshared string MemAvailable = "Available";
__gshared string MemReserved = "Reserved";

struct Framebuffer
{
    uint* ptr;
    uint width;
    uint height;
    uint pitch;
    uint bytesPerPixel;
}

void fillScreen(
    Framebuffer* fb,
    uint color) @nogc nothrow
{
    for (uint y = 0; y < fb.height; y++)
    {
        for (uint x = 0; x < fb.width; x++)
        {
            uint offset = y * (fb.pitch / fb.bytesPerPixel) + x;
            fb.ptr[offset] = color;
        }
    }
}

void drawBitmap(
    Framebuffer* fb,
    uint x0, uint y0,
    const uint[] bitmap,
    ushort w, ushort h) @nogc nothrow
{
    for (uint y = 0; y < h; y++)
    {
        if (y0 + y >= fb.height)
            break;
        for (uint x = 0; x < w; x++)
        {
            if (x0 + x >= fb.width)
                break;
            uint offset = (y0 + y) * (fb.pitch / fb.bytesPerPixel) + (x0 + x);
            uint pix = bitmap[y * w + x];
            if (pix != 0x00FF00FF)
                fb.ptr[offset] = bitmap[y * w + x];
        }
    }
}

struct MouseState
{
    int x;
    int y;
    ubyte buttons;  // 0x1=left, 0x2=right, 0x4=middle
}

__gshared MouseState mouseState;
__gshared ubyte[3] packet;
__gshared ubyte packetIndex = 0;

enum: ubyte
{
    PS2_DATA_PORT  = 0x60,
    PS2_STATUS_PORT = 0x64,
    PS2_CMD_MOUSE = 0xD4,
    PS2_ENABLE_MOUSE = 0xF4
};

void mouse_handle_byte(uint val) @nogc nothrow
{
    packet[packetIndex] = cast(ubyte)val;
    packetIndex++;

    if (packetIndex == 3)
    {
        ubyte b0 = packet[0];
        ubyte b1 = packet[1];
        ubyte b2 = packet[2];

        int dx = cast(int)b1;
        int dy = cast(int)b2;

        if (b0 & 0x10) dx -= 256; // X sign
        if (b0 & 0x20) dy -= 256; // Y sign

        mouseState.x += dx;
        mouseState.y -= dy;

        if (mouseState.x < 0) mouseState.x = 0;
        if (mouseState.x > 639) mouseState.x = 639;
        if (mouseState.y < 0) mouseState.y = 0;
        if (mouseState.y > 479) mouseState.y = 479;

        mouseState.buttons = b0 & 0x07; 

        packetIndex = 0;
    }
}

void pollMouse() @nogc nothrow
{
    if (kPortReadByte(PS2_STATUS_PORT) & 0x01)
    {
        ubyte val = kPortReadByte(PS2_DATA_PORT);
        if (packetIndex == 0) {
            if ((val & 0x08) == 0) return;
        }
        
        packet[packetIndex] = val;
        packetIndex++;
        if (packetIndex == 3)
        {
            ubyte b0 = packet[0];
            byte dx = packet[1];
            byte dy = packet[2];
            
            mouseState.x += dx;
            mouseState.y -= dy;
            
            if (mouseState.x < 0) mouseState.x = 0;
            if (mouseState.x > 639) mouseState.x = 639;
            if (mouseState.y < 0) mouseState.y = 0;
            if (mouseState.y > 479) mouseState.y = 479;
            
            mouseState.buttons = b0 & 0x07;
            
            packetIndex = 0;
        }
    }
}

enum PIT_CHANNEL0 = 0x40;
enum PIT_COMMAND = 0x43;
enum  PIT_FREQUENCY = 1193182; // In Hz

ushort pitRead() @nogc nothrow
{
    kPortWriteByte(PIT_COMMAND, 0x00);
    ubyte pitLow  = kPortReadByte(PIT_CHANNEL0);
    ubyte pitHigh = kPortReadByte(PIT_CHANNEL0);
    return (pitHigh << 8) | pitLow;
}

__gshared uint t_high = 0;
__gshared ushort t_prev = 0xFFFF;

uint pitTimeTicks() @nogc nothrow
{
    ushort t_curr = pitRead();
    if (t_curr > t_prev)
        t_high += 0x10000;
    t_prev = t_curr;
    return t_high + (0xFFFF - t_curr);
}

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

    vbe_info* vbe;
    kprintf("Video:\n");
    if ((mbi.flags & MULTIBOOT_INFO_VIDEO_INFO) != 0)
    {
        kprintf(" vbe_mode_info: %x\n", mbi.vbe_mode_info);
        kprintf(" vbe_mode: %u\n", mbi.vbe_mode);
        vbe = cast(vbe_info*)mbi.vbe_mode_info;
    } else {
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
    
    packetIndex = 0;
    mouseState.x = 0;
    mouseState.y = 0;
    mouseState.buttons = 0;
    while (kPortReadByte(PS2_STATUS_PORT) & 0x02) {}
    kPortWriteByte(PS2_STATUS_PORT, PS2_CMD_MOUSE);
    while (kPortReadByte(PS2_STATUS_PORT) & 0x02) {}
    kPortWriteByte(PS2_DATA_PORT, PS2_ENABLE_MOUSE);
    
    uint time1 = pitTimeTicks();
    uint renderTimer = 0;
    uint mouseTimer = 0;
    
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
            pollMouse();
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

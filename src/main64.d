module main64;

import bootloader.limine;
import core.port;
import logo;
import cursor;

extern(C):

void* memcpy(void* dest, const void* src, size_t n) @nogc nothrow
{
    auto d = cast(ubyte*)dest;
    auto s = cast(const ubyte*)src;
    for (size_t i = 0; i < n; i++)
    {
        d[i] = s[i];
    }
    return dest;
}

void* memset(void *s, int c, size_t n) @nogc nothrow
{
    ubyte* p = cast(ubyte*)s;

    for (size_t i = 0; i < n; i++)
    {
        p[i] = cast(ubyte)c;
    }

    return s;
}

// Halt and catch fire
void hcf() @nogc nothrow
{
    for (;;) asm @nogc nothrow
    {
        hlt;
    }
}

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
__gshared uint mouseBoundH = 0;
__gshared uint mouseBoundV = 0;

enum: ubyte
{
    PS2_DATA_PORT  = 0x60,
    PS2_STATUS_PORT = 0x64,
    PS2_CMD_MOUSE = 0xD4,
    PS2_ENABLE_MOUSE = 0xF4
};

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
            if (mouseState.x > mouseBoundH) mouseState.x = mouseBoundH;
            if (mouseState.y < 0) mouseState.y = 0;
            if (mouseState.y > mouseBoundV) mouseState.y = mouseBoundV;
            
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
    
    /*
    if (resp.framebuffer_count > 1)
    {
        for (ulong i = 0; i < resp.framebuffer_count; i++)
        {
            auto _fb = resp.framebuffers[i];
            if (_fb.bpp == 32)
            {
                fb = _fb;
            }
        }
    }
    */
    
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
    
    mouseBoundH = cast(uint)fb.width - 1;
    mouseBoundV = cast(uint)fb.height - 1;
    
    packetIndex = 0;
    mouseState.x = 0;
    mouseState.y = 0;
    mouseState.buttons = 0;
    
    while (kPortReadByte(PS2_STATUS_PORT) & 0x02) {}
    kPortWriteByte(PS2_STATUS_PORT, PS2_CMD_MOUSE);

    while (kPortReadByte(PS2_STATUS_PORT) & 0x02) {}
    kPortWriteByte(PS2_DATA_PORT, PS2_ENABLE_MOUSE);
    
    fillScreen(&frontBuffer, 0x000000AA);
    
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
    }
}

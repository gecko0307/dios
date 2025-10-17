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

// Halt and catch fire
void hcf() @nogc nothrow
{
    for (;;) asm @nogc nothrow
    {
        hlt;
    }
}

void fillScreen(
    LimineFramebuffer* fb,
    uint color) @nogc nothrow
{
    uint* fb_ptr = cast(uint*)fb.address;
    for (ulong y = 0; y < fb.height; y++)
    {
        for (ulong x = 0; x < fb.width; x++)
        {
            ulong offset = y * fb.width + x;
            fb_ptr[offset] = color;
        }
    }
}

void drawBitmap(
    LimineFramebuffer* fb,
    uint x0, uint y0,
    const uint[] bitmap,
    uint w, uint h) @nogc nothrow
{
    uint* fb_ptr = cast(uint*)fb.address;
    for (uint y = 0; y < h; y++)
    {
        if (y0 + y >= fb.height)
            break;
        for (uint x = 0; x < w; x++)
        {
            if (x0 + x >= fb.width)
                break;
            ulong offset = (y0 + y) * fb.width + (x0 + x);
            uint pix = bitmap[y * w + x];
            if (pix != 0x00FF00FF)
                fb_ptr[offset] = bitmap[y * w + x];
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

void kmain() @nogc nothrow
{
    auto resp = framebufferRequest.response;
    while (resp is null || resp.framebuffer_count < 1)
    {
        asm @nogc nothrow { hlt; }
        resp = framebufferRequest.response;
    }
    
    auto fb = resp.framebuffers[0];
    
    packetIndex = 0;
    mouseState.x = 0;
    mouseState.y = 0;
    mouseState.buttons = 0;
    
    while (kPortReadByte(PS2_STATUS_PORT) & 0x02) {}
    kPortWriteByte(PS2_STATUS_PORT, PS2_CMD_MOUSE);

    while (kPortReadByte(PS2_STATUS_PORT) & 0x02) {}
    kPortWriteByte(PS2_DATA_PORT, PS2_ENABLE_MOUSE);
    
    fillScreen(fb, 0x000000AA);
    drawBitmap(fb, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
    
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
        
        /*
        if (renderTimer >= 16666) // 16.7 millisecs
        {
            // Render
            fillScreen(fb, 0x000000AA);
            drawBitmap(fb, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
            drawBitmap(fb, mouseState.x, mouseState.y, CURSOR, CURSOR_WIDTH, CURSOR_HEIGHT);
            
            // TODO: double buffering
            renderTimer = 0;
        }
        */
    }
}

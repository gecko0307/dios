module core.ps2;

import core.port;

enum PS2: ubyte
{
    DataPort = 0x60,
    StatusPort = 0x64,
    CommandPort = 0x64,
    
    CmdMouse = 0xD4,
    CmdEnableMouse = 0xF4
};

struct PS2MouseState
{
    ubyte[3] packet;
    ubyte packetIndex;
    int x;
    int y;
    uint xBound = 0; // Maximum x-coordinate
    uint yBound = 0; // Maximum y-coordinate
    ubyte buttons;  // 0x1=left, 0x2=right, 0x4=middle
}

__gshared PS2MouseState ps2MouseState;

extern(C):

PS2MouseState* ps2MouseInit(uint xBound, uint yBound) @nogc nothrow
{
    ps2MouseState.packetIndex = 0;
    ps2MouseState.x = 0;
    ps2MouseState.y = 0;
    ps2MouseState.xBound = xBound;
    ps2MouseState.yBound = yBound;
    ps2MouseState.buttons = 0;
    
    //while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    //kPortWriteByte(PS2.CommandPort, 0xA8); // Enable auxiliary device
    
    while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    kPortWriteByte(PS2.CommandPort, PS2.CmdMouse);

    while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    kPortWriteByte(PS2.DataPort, PS2.CmdEnableMouse);
    
    return &ps2MouseState;
}

void ps2MousePoll() @nogc nothrow
{
    if (kPortReadByte(PS2.StatusPort) & 0x01)
    {
        ubyte val = kPortReadByte(PS2.DataPort);
        if (ps2MouseState.packetIndex == 0) {
            if ((val & 0x08) == 0) return;
        }
        
        ps2MouseState.packet[ps2MouseState.packetIndex] = val;
        ps2MouseState.packetIndex++;
        if (ps2MouseState.packetIndex == 3)
        {
            ubyte b0 = ps2MouseState.packet[0];
            byte dx = ps2MouseState.packet[1];
            byte dy = ps2MouseState.packet[2];
            
            ps2MouseState.x += dx;
            ps2MouseState.y -= dy;
            
            if (ps2MouseState.x < 0) ps2MouseState.x = 0;
            if (ps2MouseState.x > ps2MouseState.xBound) ps2MouseState.x = ps2MouseState.xBound;
            if (ps2MouseState.y < 0) ps2MouseState.y = 0;
            if (ps2MouseState.y > ps2MouseState.yBound) ps2MouseState.y = ps2MouseState.yBound;
            
            ps2MouseState.buttons = b0 & 0x07;
            
            ps2MouseState.packetIndex = 0;
        }
    }
}

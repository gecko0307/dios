module core.ps2;

import core.port;

enum PS2: ubyte
{
    DataPort = 0x60,
    StatusPort = 0x64,
    CommandPort = 0x64,
    
    CmdEnableKeyboard = 0xAE,
    CmdEnableAuxiliaryDevice = 0xA8,
    CmdMouse = 0xD4,
    CmdEnableMouse = 0xF4
};

struct PS2State
{
    ubyte[3] packet;
    ubyte keyPressed;
    ubyte lastScancode;
    ubyte extended;
    ubyte packetIndex;
    ubyte mbuttons;  // 0x1=left, 0x2=right, 0x4=middle
    int mx;
    int my;
    uint xBound = 0; // Maximum x-coordinate
    uint yBound = 0; // Maximum y-coordinate
}

__gshared PS2State ps2State;

extern(C):

PS2State* ps2Init(uint xBound, uint yBound) @nogc nothrow
{
    ps2State.keyPressed = 0;
    ps2State.lastScancode = 0;
    ps2State.extended = 0;
    ps2State.packetIndex = 0;
    ps2State.mbuttons = 0;
    ps2State.mx = 0;
    ps2State.my = 0;
    ps2State.xBound = xBound;
    ps2State.yBound = yBound;
    
    while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    kPortWriteByte(PS2.CommandPort, 0xFF);
    
    while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    kPortWriteByte(PS2.CommandPort, PS2.CmdEnableKeyboard);
    
    // Flush the keyboard
    while ((kPortReadByte(PS2.StatusPort) & 0x01) != 0)
    {
        ubyte tmp = kPortReadByte(PS2.DataPort);
    }
    
    while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    kPortWriteByte(PS2.CommandPort, PS2.CmdEnableAuxiliaryDevice);
    
    while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    kPortWriteByte(PS2.CommandPort, PS2.CmdMouse);

    while (kPortReadByte(PS2.StatusPort) & 0x02) {}
    kPortWriteByte(PS2.DataPort, PS2.CmdEnableMouse);
    
    return &ps2State;
}

void ps2Poll() @nogc nothrow
{
    ubyte status = kPortReadByte(PS2.StatusPort);
    if (status & 0x20)
    {
        // Mouse
        ubyte val = kPortReadByte(PS2.DataPort);
        if (ps2State.packetIndex == 0)
        {
            if ((val & 0x08) == 0) return;
        }
        
        ps2State.packet[ps2State.packetIndex] = val;
        ps2State.packetIndex++;
        if (ps2State.packetIndex == 3)
        {
            ubyte b0 = ps2State.packet[0];
            byte dx = ps2State.packet[1];
            byte dy = ps2State.packet[2];
            
            ps2State.mx += dx;
            ps2State.my -= dy;
            
            if (ps2State.mx < 0) ps2State.mx = 0;
            if (ps2State.mx > ps2State.xBound) ps2State.mx = ps2State.xBound;
            if (ps2State.my < 0) ps2State.my = 0;
            if (ps2State.my > ps2State.yBound) ps2State.my = ps2State.yBound;
            
            ps2State.mbuttons = b0 & 0x07;
            
            ps2State.packetIndex = 0;
        }
    }
    else if (status & 0x01)
    {
        ubyte sc = kPortReadByte(PS2.DataPort);

        if (sc == 0xE0)
        {
            ps2State.extended = 1;
        }
        else
        {
            ps2State.keyPressed = true;
            ps2State.lastScancode = sc;
            ubyte ext = ps2State.extended;
            ps2State.extended = 0;
        }
    }
}

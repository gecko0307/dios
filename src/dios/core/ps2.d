module dios.core.ps2;

import dios.core.port;
import dios.core.mouse;

enum PS2: ubyte
{
    DataPort = 0x60,
    StatusPort = 0x64,
    CommandPort = 0x64,

    CmdEnableKeyboard = 0xAE,
    CmdEnableAuxiliaryDevice = 0xA8,
    CmdReadConfig = 0x20,
    CmdWriteConfig = 0x60,
    CmdMouse = 0xD4,

    MouseSetDefaults = 0xF6,
    MouseEnableReporting = 0xF4,
    Ack = 0xFA
};

struct PS2State
{
    ubyte[3] packet;
    ubyte keyPressed;
    ubyte lastScancode;
    ubyte extended;
    ubyte packetIndex;
    bool present;      // an 8042 controller answered
    bool mouseOk;      // the mouse acknowledged F4
}

__gshared PS2State ps2State;

extern(C):

// All waits are bounded. The old code spun forever; on a machine with no
// 8042 (many UEFI/USB-only PCs) port 0x64 reads 0xFF, "input buffer full"
// never clears and the kernel hangs right here.
bool ps2WaitInputClear() @nogc nothrow
{
    for (uint i = 0; i < 100000; i++)
        if ((kPortReadByte(PS2.StatusPort) & 0x02) == 0)
            return true;
    return false;
}

bool ps2WaitOutputFull() @nogc nothrow
{
    for (uint i = 0; i < 100000; i++)
        if ((kPortReadByte(PS2.StatusPort) & 0x01) != 0)
            return true;
    return false;
}

int ps2ReadData() @nogc nothrow
{
    if (!ps2WaitOutputFull())
        return -1;
    return kPortReadByte(PS2.DataPort);
}

bool ps2WriteCommand(ubyte cmd) @nogc nothrow
{
    if (!ps2WaitInputClear()) return false;
    kPortWriteByte(PS2.CommandPort, cmd);
    return true;
}

bool ps2WriteData(ubyte data) @nogc nothrow
{
    if (!ps2WaitInputClear()) return false;
    kPortWriteByte(PS2.DataPort, data);
    return true;
}

void ps2Flush() @nogc nothrow
{
    for (uint i = 0; i < 64 && (kPortReadByte(PS2.StatusPort) & 0x01) != 0; i++)
        kPortReadByte(PS2.DataPort);
}

// Send a command to the mouse and wait for its ACK (0xFA).
bool ps2MouseCommand(ubyte cmd) @nogc nothrow
{
    if (!ps2WriteCommand(PS2.CmdMouse)) return false;
    if (!ps2WriteData(cmd)) return false;
    return ps2ReadData() == PS2.Ack;
}

bool ps2Init() @nogc nothrow
{
    ps2State = PS2State.init;

    if (kPortReadByte(PS2.StatusPort) == 0xFF)
        return false;                       // no controller
    ps2State.present = true;

    ps2Flush();
    ps2WriteCommand(PS2.CmdEnableKeyboard);
    ps2WriteCommand(PS2.CmdEnableAuxiliaryDevice);   // was commented out

    // Config byte: we poll, so disable both IRQs (bits 0,1) and make sure
    // both port clocks are enabled (bits 4,5). Translation (bit 6) untouched.
    if (ps2WriteCommand(PS2.CmdReadConfig))
    {
        int cfg = ps2ReadData();
        if (cfg >= 0)
        {
            cfg &= ~((1 << 0) | (1 << 1) | (1 << 4) | (1 << 5));
            ps2WriteCommand(PS2.CmdWriteConfig);
            ps2WriteData(cast(ubyte)cfg);
        }
    }
    ps2Flush();

    // The mouse ACKs every command with 0xFA. The old code never read that
    // ACK, so ps2Poll took it for the first byte of a packet (0xFA has bit 3
    // set, so it even passed the sync check) and every packet after that was
    // shifted by one byte - phantom right-clicks and a jumping cursor.
    ps2MouseCommand(PS2.MouseSetDefaults);
    ps2State.mouseOk = ps2MouseCommand(PS2.MouseEnableReporting);
    ps2Flush();

    return true;
}

void ps2HandleMouseByte(ubyte val) @nogc nothrow
{
    // Byte 0 always has bit 3 set - use that to resynchronise.
    if (ps2State.packetIndex == 0 && (val & 0x08) == 0)
        return;

    ps2State.packet[ps2State.packetIndex] = val;
    ps2State.packetIndex++;
    if (ps2State.packetIndex < 3)
        return;
    ps2State.packetIndex = 0;

    ubyte b0 = ps2State.packet[0];
    if (b0 & 0xC0)
        return;                             // x/y overflow: drop the packet

    // 9-bit two's complement: sign bits live in byte 0.
    int dx = cast(int)ps2State.packet[1] - ((b0 << 4) & 0x100);
    int dy = cast(int)ps2State.packet[2] - ((b0 << 3) & 0x100);
    mouseMove(dx, -dy, b0 & 0x07);          // PS/2: +y is up
}

void ps2HandleKeyByte(ubyte sc) @nogc nothrow
{
    if (sc == 0xE0)
    {
        ps2State.extended = 1;
        return;
    }
    ps2State.extended = 0;
    if (sc & 0x80)
        return;                             // key release
    ps2State.keyPressed = 1;
    ps2State.lastScancode = sc;
}

void ps2Poll() @nogc nothrow
{
    if (!ps2State.present)
        return;

    // Drain what is there instead of one byte per call.
    for (uint n = 0; n < 16; n++)
    {
        ubyte status = kPortReadByte(PS2.StatusPort);
        if (!(status & 0x01))
            return;
        ubyte val = kPortReadByte(PS2.DataPort);
        if (status & 0x20)
            ps2HandleMouseByte(val);
        else
            ps2HandleKeyByte(val);
    }
}

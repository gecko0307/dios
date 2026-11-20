module dios.core.ps2;

import dios.core.port;
import dios.core.mouse;
import dios.core.cpu;
import dios.core.idt;
import dios.core.ioapic;

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
    ubyte extended;
    ubyte shiftMask;   // bit 0: left Shift held, bit 1: right Shift held
    ubyte packetIndex;
    bool present;      // an 8042 controller answered
    bool mouseOk;      // the mouse acknowledged F4
    bool irqMode;      // bytes arrive through IRQ1/IRQ12 instead of being polled
}

enum uint PS2_RING_SIZE = 256;   // power of two
enum uint PS2_KEYQ_SIZE = 64;    // power of two

// Two single-producer/single-consumer queues:
//  - raw bytes: filled by the interrupt handler, drained by the main loop
//  - key events: filled and drained by the main loop (a press = scancode + Shift snapshot)
struct PS2Queues
{
    ushort[PS2_RING_SIZE] raw;   // (isMouse << 8) | byte
    uint rawHead;                // written only by the IRQ handler
    uint rawTail;                // written only by the consumer, with interrupts off
    ushort[PS2_KEYQ_SIZE] keys;  // (shift << 8) | scancode
    uint keyHead;
    uint keyTail;
    uint rawDropped;
}

__gshared PS2State ps2State;
__gshared PS2Queues ps2q;

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
    ps2q = PS2Queues.init;

    if (kPortReadByte(PS2.StatusPort) == 0xFF)
        return false; // no controller
    ps2State.present = true;

    ps2Flush();
    ps2WriteCommand(PS2.CmdEnableKeyboard);
    ps2WriteCommand(PS2.CmdEnableAuxiliaryDevice); // was commented out

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
        return; // x/y overflow: drop the packet

    // 9-bit two's complement: sign bits live in byte 0.
    int dx = cast(int)ps2State.packet[1] - ((b0 << 4) & 0x100);
    int dy = cast(int)ps2State.packet[2] - ((b0 << 3) & 0x100);
    mouseMove(dx, -dy, b0 & 0x07); // PS/2: +y is up
}

void ps2HandleKeyByte(ubyte sc) @nogc nothrow
{
    if (sc == 0xE0)
    {
        ps2State.extended = 1;
        return;
    }
    bool ext = ps2State.extended != 0;
    ps2State.extended = 0;

    bool release = (sc & 0x80) != 0;
    ubyte code = sc & 0x7F;

    // Shift: 0x2A left, 0x36 right. Track the two separately so releasing one
    // while holding the other keeps Shift active. The E0-prefixed 0x2A/0x36
    // that some keyboards send around arrows/Insert/etc. are "fake shifts" and
    // must not change the state.
    if (!ext && (code == 0x2A || code == 0x36))
    {
        ubyte bit = cast(ubyte)((code == 0x2A) ? 1 : 2);
        if (release)
            ps2State.shiftMask = cast(ubyte)(ps2State.shiftMask & ~bit);
        else
            ps2State.shiftMask = cast(ubyte)(ps2State.shiftMask | bit);
        return;
    }

    if (release)
        return; // key release

    // Queue the press with a Shift snapshot taken now, so it stays correct even if
    // Shift is released again before the main loop gets to it.
    uint next = ps2q.keyHead + 1;
    if (next - ps2q.keyTail > PS2_KEYQ_SIZE)
        return; // queue full: drop the key
    ushort shifted = cast(ushort)((ps2State.shiftMask != 0) ? 0x100 : 0);
    ps2q.keys[ps2q.keyHead & (PS2_KEYQ_SIZE - 1)] = cast(ushort)(shifted | sc);
    ps2q.keyHead = next;
}

/// Next key press, in order. `scancode` is the set-1 make code, `shift` whether Shift was down.
bool ps2PopKey(ubyte* scancode, bool* shift) @nogc nothrow
{
    if (ps2q.keyTail == ps2q.keyHead)
        return false;
    ushort e = ps2q.keys[ps2q.keyTail & (PS2_KEYQ_SIZE - 1)];
    ps2q.keyTail++;
    *scancode = cast(ubyte)(e & 0xFF);
    *shift = (e & 0x100) != 0;
    return true;
}

// Polled mode: drain what is there instead of one byte per call.
void ps2Poll() @nogc nothrow
{
    if (!ps2State.present)
        return;

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

// IRQ1 and IRQ12 handler. Runs with interrupts off: only moves bytes into the
// raw ring - decoding (and anything that draws) happens in the main loop.
extern(C) void ps2Irq(InterruptFrame* f) @nogc nothrow
{
    for (uint n = 0; n < 16; n++)
    {
        ubyte status = kPortReadByte(PS2.StatusPort);
        if (!(status & 0x01))
            return;
        ubyte val = kPortReadByte(PS2.DataPort);
        uint next = ps2q.rawHead + 1;
        if (next - ps2q.rawTail > PS2_RING_SIZE)
        {
            ps2q.rawDropped++;
            continue;
        }
        ps2q.raw[ps2q.rawHead & (PS2_RING_SIZE - 1)] = cast(ushort)(((status & 0x20) ? 0x100 : 0) | val);
        ps2q.rawHead = next;
    }
}

// Decode everything the IRQ handler has queued. Call from the main loop.
void ps2Drain() @nogc nothrow
{
    for (;;)
    {
        ulong flags = cpuIrqSave();         // the IRQ handler owns rawHead; keep it out while we look
        bool have = ps2q.rawTail != ps2q.rawHead;
        ushort e = 0;
        if (have)
        {
            e = ps2q.raw[ps2q.rawTail & (PS2_RING_SIZE - 1)];
            ps2q.rawTail++;
        }
        cpuIrqRestore(flags);

        if (!have)
            return;
        if (e & 0x100)
            ps2HandleMouseByte(cast(ubyte)(e & 0xFF));
        else
            ps2HandleKeyByte(cast(ubyte)(e & 0xFF));
    }
}

/// Switch from polling to interrupts: route IRQ1/IRQ12 through the IOAPIC to
/// `destApicId`, then let the 8042 raise them. Returns false (and stays in polled
/// mode) if the keyboard line cannot be routed.
bool ps2StartIrq(uint destApicId) @nogc nothrow
{
    if (!ps2State.present)
        return false;

    int kbdGsi = ioapicRouteIsa(1, VEC_KEYBOARD, destApicId);
    if (kbdGsi < 0)
        return false;
    int mouseGsi = ioapicRouteIsa(12, VEC_MOUSE, destApicId);

    irqRegister(VEC_KEYBOARD, &ps2Irq);
    irqRegister(VEC_MOUSE, &ps2Irq);

    // Controller configuration byte: bit 0 = IRQ1 enable, bit 1 = IRQ12 enable.
    if (!ps2WriteCommand(PS2.CmdReadConfig))
        return false;
    int cfg = ps2ReadData();
    if (cfg < 0)
        return false;
    cfg |= 1;
    if (mouseGsi >= 0 && ps2State.mouseOk)
        cfg |= 2;
    ps2Flush();
    ps2State.irqMode = true;            // from here on the IRQ handler owns the data port
    ps2WriteCommand(PS2.CmdWriteConfig);
    ps2WriteData(cast(ubyte)cfg);
    return true;
}

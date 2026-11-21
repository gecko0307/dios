module dios.core.pit;

import dios.core.port;

enum PIT: ubyte
{
    CommandPort = 0x43,
    Channel0 = 0x40
}

enum PIT_FREQUENCY = 1193182; // In Hz

// Monotonic tick counter (1 tick = 1/1193182 s, wraps after ~490000 years).
__gshared ulong pitTicks = 0;
__gshared ushort pitPrevCount = 0;

extern(C):

ushort pitRead() @nogc nothrow
{
    kPortWriteByte(PIT.CommandPort, 0x00); // latch channel 0
    ubyte pitLow  = kPortReadByte(PIT.Channel0);
    ubyte pitHigh = kPortReadByte(PIT.Channel0);
    return cast(ushort)((pitHigh << 8) | pitLow);
}

// Program channel 0 ourselves: rate generator (mode 2), reload 65536.
// Under UEFI nobody promises the PIT is configured.
void pitInit() @nogc nothrow
{
    kPortWriteByte(PIT.CommandPort, 0x34);
    kPortWriteByte(PIT.Channel0, 0x00);
    kPortWriteByte(PIT.Channel0, 0x00);
    pitTicks = 0;
    pitPrevCount = pitRead();
}

// Must be called at least once every ~54 ms (one full counter wrap).
// The counter counts DOWN, so elapsed = prev - cur, modulo 65536.
ulong pitTimeTicks() @nogc nothrow
{
    ushort cur = pitRead();
    pitTicks += cast(ushort)(pitPrevCount - cur);
    pitPrevCount = cur;
    return pitTicks;
}

void pitDelayUs(uint us) @nogc nothrow
{
    ulong target = pitTimeTicks() + (cast(ulong)us * PIT_FREQUENCY) / 1000000 + 1;
    while (pitTimeTicks() < target) {}
}

void pitDelayMs(uint ms) @nogc nothrow
{
    pitDelayUs(ms * 1000);
}

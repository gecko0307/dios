module core.pit;

import core.port;

enum PIT: ubyte
{
    CommandPort = 0x43,
    Channel0 = 0x40
}

enum PIT_FREQUENCY = 1193182; // In Hz

__gshared uint t_high = 0;
__gshared ushort t_prev = 0xFFFF;

extern(C):

ushort pitRead() @nogc nothrow
{
    kPortWriteByte(PIT.CommandPort, 0x00);
    ubyte pitLow  = kPortReadByte(PIT.Channel0);
    ubyte pitHigh = kPortReadByte(PIT.Channel0);
    return (pitHigh << 8) | pitLow;
}

uint pitTimeTicks() @nogc nothrow
{
    ushort t_curr = pitRead();
    if (t_curr > t_prev)
        t_high += 0x10000;
    t_prev = t_curr;
    return t_high + (0xFFFF - t_curr);
}

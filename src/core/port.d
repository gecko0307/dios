module core.port;

extern(C):

ubyte kPortReadByte(ushort port) @nogc nothrow;
void kPortWriteByte(ushort port, ubyte value) @nogc nothrow;

version(X86_64)
{
    uint kPortRead32(ushort port) @nogc nothrow;
    void kPortWrite32(ushort port, uint value) @nogc nothrow;
}

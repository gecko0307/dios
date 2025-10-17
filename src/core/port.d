module core.port;

extern(C):

ubyte kPortReadByte(ushort port) @nogc nothrow;
void kPortWriteByte(ushort port, ubyte value) @nogc nothrow;

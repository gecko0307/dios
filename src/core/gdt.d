module core.gdt;

struct GDTEntry
{
   align(1):
    ushort limitLow;
    ushort baseLow;
    ubyte baseMid;
    ubyte access;
    ubyte granularity;
    ubyte baseHigh;
}

struct GDTR
{
   align(1):
    ushort limit;
    uint base;
}

__gshared GDTEntry[3] gdt; // 0=null, 1=code, 2=data
__gshared GDTR gdtr;

extern(C):

void setGDTEntry(int i, uint base, uint limit, ubyte access, ubyte gran) @nogc nothrow
{
    gdt[i].limitLow    = cast(ushort)(limit & 0xFFFF);
    gdt[i].baseLow     = cast(ushort)(base & 0xFFFF);
    gdt[i].baseMid     = cast(ubyte)((base >> 16) & 0xFF);
    gdt[i].access      = access;
    gdt[i].granularity = cast(ubyte)(((limit >> 16) & 0x0F) | (gran & 0xF0));
    gdt[i].baseHigh    = cast(ubyte)((base >> 24) & 0xFF);
}

// asm function
void load_gdt(GDTR*) @nogc nothrow;

void initGDT() @nogc nothrow
{
    // Null descriptor
    setGDTEntry(0, 0, 0, 0, 0);

    // Code segment: base=0, limit=4GB, access=0x9A, gran=0xCF
    // 0x9A = 10011010b = present, ring0, code, readable
    // 0xCF = 11001111b = granularity=4K, 32-bit, limit=FFFFF
    setGDTEntry(1, 0, 0xFFFFF, 0x9A, 0xCF);

    // Data segment: base=0, limit=4GB, access=0x92, gran=0xCF
    // 0x92 = 10010010b = present, ring0, data, writable
    setGDTEntry(2, 0, 0xFFFFF, 0x92, 0xCF);

    gdtr.limit = cast(ushort)(gdt.sizeof - 1);
    gdtr.base  = cast(uint)&gdt[0];

    load_gdt(&gdtr);
}

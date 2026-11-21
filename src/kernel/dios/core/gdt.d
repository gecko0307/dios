module dios.core.gdt;

/**
 * Our own GDT + TSS).
 *
 *   0x00 null
 *   0x08 kernel code (64-bit)      0x10 kernel data
 *   0x18 user data                 0x20 user code (64-bit)   <- SYSRET-friendly order
 *   0x28 TSS (16-byte descriptor)
 *
 * The TSS carries the Interrupt Stack Table. Every external interrupt runs on
 * IST1, so it never touches the interrupted code's stack - which means it does
 * not matter whether the kernel was compiled with the red zone. NMI, double
 * fault and machine check get their own stack (IST2) so a blown kernel stack
 * still produces a register dump instead of a triple fault.
 */
import dios.core.cpu;

enum ushort GDT_KERNEL_CODE = 0x08;
enum ushort GDT_KERNEL_DATA = 0x10;
enum ushort GDT_USER_DATA   = 0x18;
enum ushort GDT_USER_CODE   = 0x20;
enum ushort GDT_TSS         = 0x28;

enum uint IST_IRQ   = 1;
enum uint IST_FAULT = 2;

enum size_t IST_STACK_SIZE = 16384;

struct Tss
{
    align(1):
    uint reserved0;
    ulong rsp0;
    ulong rsp1;
    ulong rsp2;
    ulong reserved1;
    ulong[7] ist;       // ist[0] is IST1
    ulong reserved2;
    ushort reserved3;
    ushort iomapBase;
}
static assert(Tss.sizeof == 104);

struct Gdtr
{
    align(1):
    ushort limit;
    ulong base;
}
static assert(Gdtr.sizeof == 10);

align(16) __gshared ubyte[IST_STACK_SIZE] istIrqStack;
align(16) __gshared ubyte[IST_STACK_SIZE] istFaultStack;
align(16) __gshared ubyte[IST_STACK_SIZE] ring0Stack;   // TSS.rsp0, for a future ring 3
align(16) __gshared ulong[7] gdtTable;
__gshared Tss tss;
__gshared Gdtr gdtr;

extern(C):

void gdtInit() @nogc nothrow
{
    gdtTable[0] = 0;
    gdtTable[1] = 0x00AF9A000000FFFFUL; // kernel code: P, DPL0, exec/read, L=1, G
    gdtTable[2] = 0x00CF92000000FFFFUL; // kernel data: P, DPL0, read/write, G
    gdtTable[3] = 0x00CFF2000000FFFFUL; // user data:   DPL3
    gdtTable[4] = 0x00AFFA000000FFFFUL; // user code:   DPL3, L=1

    tss.rsp0 = cast(ulong)ring0Stack.ptr + IST_STACK_SIZE;
    tss.ist[0] = cast(ulong)istIrqStack.ptr + IST_STACK_SIZE;
    tss.ist[1] = cast(ulong)istFaultStack.ptr + IST_STACK_SIZE;
    tss.iomapBase = cast(ushort)Tss.sizeof; // no I/O permission bitmap

    ulong base = cast(ulong)&tss;
    ulong limit = Tss.sizeof - 1;
    gdtTable[5] = (limit & 0xFFFF)
                | ((base & 0xFFFFFF) << 16)
                | (0x89UL << 40)                 // present, 64-bit TSS (available)
                | (((limit >> 16) & 0xF) << 48)
                | (((base >> 24) & 0xFF) << 56);
    gdtTable[6] = base >> 32;

    gdtr.limit = cast(ushort)(gdtTable.sizeof - 1);
    gdtr.base = cast(ulong)gdtTable.ptr;

    gdtFlush(&gdtr);
    tssLoad(GDT_TSS);
}

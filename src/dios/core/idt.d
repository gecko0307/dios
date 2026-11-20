module dios.core.idt;

/**
 * IDT, interrupt dispatch and CPU exception reporting.
 *
 * Vector map
 *   0x00-0x1F  CPU exceptions (fatal for now: register dump, then halt)
 *   0x20-0x2F  legacy PIC after remap - everything is masked, never expected
 *   0x40       LAPIC timer
 *   0x41       PS/2 keyboard
 *   0x42       PS/2 mouse
 *   0x50-0xEF  dynamically allocated (MSI/MSI-X, ...)  see irqAllocVector()
 *   0xFE       LAPIC error
 *   0xFF       LAPIC spurious
 *
 * Handlers run with interrupts disabled, on the IST1 stack. They must be
 * short and must NOT call kprintf (the main loop may be in the middle of
 * drawing): record what happened, and let the main loop do the real work.
 */
import dios.core.cpu;
import dios.core.gdt;
import dios.core.lapic;
import dios.core.stdio;
import dios.core.error;

enum uint VEC_PIC_BASE     = 0x20;
enum uint VEC_TIMER        = 0x40;
enum uint VEC_KEYBOARD     = 0x41;
enum uint VEC_MOUSE        = 0x42;
enum uint VEC_DYNAMIC_FIRST = 0x50;
enum uint VEC_DYNAMIC_LAST  = 0xEF;
enum uint VEC_LAPIC_ERROR  = 0xFE;
enum uint VEC_SPURIOUS     = 0xFF;

// Layout must match the push order in cpu.s (r15 pushed last = lowest address).
struct InterruptFrame
{
    ulong r15, r14, r13, r12, r11, r10, r9, r8;
    ulong rdi, rsi, rbp, rbx, rdx, rcx, rax;
    ulong vector;
    ulong errorCode;
    ulong rip, cs, rflags, rsp, ss;
}
static assert(InterruptFrame.sizeof == 22 * 8);

alias IrqHandler = extern(C) void function(InterruptFrame*) @nogc nothrow;

struct IdtEntry
{
    ushort offsetLow;
    ushort selector;
    ubyte ist;
    ubyte typeAttr;
    ushort offsetMid;
    uint offsetHigh;
    uint zero;
}
static assert(IdtEntry.sizeof == 16);

struct Idtr
{
    align(1):
    ushort limit;
    ulong base;
}

align(16) __gshared IdtEntry[256] idtTable;
__gshared Idtr idtr;
__gshared IrqHandler[256] irqHandlers;
__gshared uint[256] irqUnhandled;      // how often a vector fired with no handler
__gshared uint nextDynamicVector = VEC_DYNAMIC_FIRST;
__gshared uint nmiCount;
__gshared bool inException;

immutable string[32] exceptionNames = [
    "Divide Error\0",               // 0
    "Debug\0",                      // 1
    "Non-Maskable Interrupt\0",     // 2
    "Breakpoint\0",                 // 3
    "Overflow\0",                   // 4
    "Bound Range Exceeded\0",       // 5
    "Invalid Opcode\0",             // 6
    "Device Not Available\0",       // 7
    "Double Fault\0",               // 8
    "Coprocessor Overrun\0",        // 9
    "Invalid TSS\0",                // 10
    "Segment Not Present\0",        // 11
    "Stack-Segment Fault\0",        // 12
    "General Protection Fault\0",   // 13
    "Page Fault\0",                 // 14
    "Reserved\0",                   // 15
    "x87 Floating-Point\0",         // 16
    "Alignment Check\0",            // 17
    "Machine Check\0",              // 18
    "SIMD Floating-Point\0",        // 19
    "Virtualization\0",             // 20
    "Control Protection\0",         // 21
    "Reserved\0", "Reserved\0", "Reserved\0", "Reserved\0", "Reserved\0", "Reserved\0", // 22-27
    "Hypervisor Injection\0",       // 28
    "VMM Communication\0",          // 29
    "Security Exception\0",         // 30
    "Reserved\0"                    // 31
];

extern(C):

void idtSetGate(uint vector, void* handler, ubyte ist) @nogc nothrow
{
    ulong h = cast(ulong)handler;
    IdtEntry* e = &idtTable[vector];
    e.offsetLow  = cast(ushort)(h & 0xFFFF);
    e.selector   = GDT_KERNEL_CODE;
    e.ist        = ist;
    e.typeAttr   = 0x8E;                 // present, DPL 0, 64-bit interrupt gate (IF cleared on entry)
    e.offsetMid  = cast(ushort)((h >> 16) & 0xFFFF);
    e.offsetHigh = cast(uint)(h >> 32);
    e.zero       = 0;
}

void idtInit() @nogc nothrow
{
    for (uint v = 0; v < 256; v++)
    {
        ubyte ist = 0;
        if (v == 2 || v == 8 || v == 18)
            ist = cast(ubyte)IST_FAULT;     // NMI, #DF, #MC: known-good stack
        else if (v >= 32)
            ist = cast(ubyte)IST_IRQ;       // external interrupts: never on the interrupted stack
        idtSetGate(v, isrStubAddress(v), ist);
        irqHandlers[v] = null;
        irqUnhandled[v] = 0;
    }

    idtr.limit = cast(ushort)(idtTable.sizeof - 1);
    idtr.base = cast(ulong)idtTable.ptr;
    idtLoad(&idtr);
}

void irqRegister(uint vector, IrqHandler handler) @nogc nothrow
{
    irqHandlers[vector & 0xFF] = handler;
}

/// Hand out an unused vector in the dynamic range (0 if exhausted).
uint irqAllocVector() @nogc nothrow
{
    if (nextDynamicVector > VEC_DYNAMIC_LAST)
        return 0;
    return nextDynamicVector++;
}

void exceptionDump(InterruptFrame* f) @nogc nothrow
{
    // A fault inside the dump itself: stop right here, nothing else is safe.
    if (inException)
        hcf();
    inException = true;

    uint v = cast(uint)f.vector;
    kprintf("\n*** CPU EXCEPTION %u: %s ***\n", v, exceptionNames[v & 31].ptr);
    kprintf("error code %llx\n", f.errorCode);
    kprintf("RIP %llx  CS %llx  RFLAGS %llx\n", f.rip, f.cs, f.rflags);
    kprintf("RSP %llx  SS %llx\n", f.rsp, f.ss);
    if (v == 14)
        kprintf("CR2 (fault address) %llx\n", cpuReadCr2());
    kprintf("RAX %llx  RBX %llx  RCX %llx\n", f.rax, f.rbx, f.rcx);
    kprintf("RDX %llx  RSI %llx  RDI %llx\n", f.rdx, f.rsi, f.rdi);
    kprintf("RBP %llx  R8  %llx  R9  %llx\n", f.rbp, f.r8, f.r9);
    kprintf("R10 %llx  R11 %llx  R12 %llx\n", f.r10, f.r11, f.r12);
    kprintf("R13 %llx  R14 %llx  R15 %llx\n", f.r13, f.r14, f.r15);
    kprintf("System halted.\n");
    hcf();
}

// Called from the assembly stubs in cpu.s.
void isrDispatch(InterruptFrame* f) @nogc nothrow
{
    uint v = cast(uint)f.vector;

    if (v == 2)
    {
        nmiCount++;                     // firmware/chipset NMIs happen on real hardware; note it and carry on
        return;
    }

    if (v < 32)
        exceptionDump(f);               // does not return

    if (v == VEC_SPURIOUS)
        return;                         // spurious: by definition no EOI

    if (v >= VEC_PIC_BASE && v < VEC_PIC_BASE + 16)
        return;                         // legacy PIC noise: it is masked, but never EOI the LAPIC for it

    IrqHandler h = irqHandlers[v];
    if (h !is null)
        h(f);
    else
        irqUnhandled[v]++;

    lapicEoi();
}

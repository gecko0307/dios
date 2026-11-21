module dios.core.lapic;

/**
 * Local APIC: per-CPU interrupt controller. Replaces the 8259 PIC and the PIT
 * interrupt. Works in xAPIC (memory-mapped) mode, and in x2APIC (MSR) mode if
 * the firmware already switched to it - we never switch modes ourselves.
 */
import core.volatile;
import dios.core.acpi;
import dios.core.clock;
import dios.core.cpu;
import dios.core.idt;
import dios.core.stdio;
import dios.core.vmem;

enum : uint
{
    LAPIC_ID        = 0x020,
    LAPIC_TPR       = 0x080,
    LAPIC_EOI       = 0x0B0,
    LAPIC_SVR       = 0x0F0,
    LAPIC_ESR       = 0x280,
    LAPIC_LVT_TIMER = 0x320,
    LAPIC_LVT_LINT0 = 0x350,
    LAPIC_LVT_LINT1 = 0x360,
    LAPIC_LVT_ERROR = 0x370,
    LAPIC_TIMER_INIT = 0x380,
    LAPIC_TIMER_CUR  = 0x390,
    LAPIC_TIMER_DIV  = 0x3E0
}

enum uint LVT_MASKED   = 1u << 16;
enum uint LVT_PERIODIC = 1u << 17;
enum uint LVT_NMI      = 4u << 8;   // delivery mode NMI
enum uint SVR_ENABLE   = 1u << 8;

__gshared ubyte* lapicRegs;
__gshared bool lapicX2;
__gshared bool lapicReady;
__gshared uint lapicErrors;
__gshared ulong lapicTimerFreq;     // timer counts per second at divide-by-16

extern(C):

uint lapicRead(uint reg) @nogc nothrow
{
    if (lapicX2)
        return cast(uint)cpuReadMsr(0x800 + (reg >> 4));
    return volatileLoad(cast(uint*)(lapicRegs + reg));
}

void lapicWrite(uint reg, uint value) @nogc nothrow
{
    if (lapicX2)
        cpuWriteMsr(0x800 + (reg >> 4), value);
    else
        volatileStore(cast(uint*)(lapicRegs + reg), value);
}

uint lapicId() @nogc nothrow
{
    if (lapicX2)
        return lapicRead(LAPIC_ID);         // full 32-bit ID in x2APIC mode
    return lapicRead(LAPIC_ID) >> 24;
}

void lapicEoi() @nogc nothrow
{
    if (lapicReady)
        lapicWrite(LAPIC_EOI, 0);
}

extern(C) void lapicErrorIrq(InterruptFrame* f) @nogc nothrow
{
    lapicWrite(LAPIC_ESR, 0);   // latch the error bits
    lapicRead(LAPIC_ESR);
    lapicErrors++;
}

/// Enable the local APIC of the boot CPU. Needs vmemInit() (xAPIC MMIO mapping).
bool lapicInit() @nogc nothrow
{
    if (!cpuHasApic())
        return false;

    ulong base = cpuReadMsr(MSR_APIC_BASE);
    lapicX2 = (base & (1UL << 10)) != 0;
    if (!(base & (1UL << 11)))              // globally disabled by firmware: turn it on
    {
        base |= (1UL << 11);
        cpuWriteMsr(MSR_APIC_BASE, base);
    }

    if (!lapicX2)
    {
        ulong phys = base & 0x000FFFFFFFFFF000UL;
        if (phys == 0)
            phys = acpi.lapicAddr;
        if (phys == 0)
            return false;
        lapicRegs = cast(ubyte*)vmemMapMMIO(phys, 4096);
        if (lapicRegs is null)
            return false;
    }
    lapicReady = true;

    irqRegister(VEC_LAPIC_ERROR, &lapicErrorIrq);

    lapicWrite(LAPIC_TPR, 0);                                   // accept every priority
    lapicWrite(LAPIC_LVT_TIMER, LVT_MASKED | VEC_TIMER);
    lapicWrite(LAPIC_LVT_LINT0, LVT_MASKED);                    // ExtINT from the PIC: unused
    lapicWrite(LAPIC_LVT_LINT1, LVT_NMI);                       // conventional wiring of the NMI pin
    lapicWrite(LAPIC_LVT_ERROR, VEC_LAPIC_ERROR);
    lapicWrite(LAPIC_SVR, SVR_ENABLE | VEC_SPURIOUS);           // software enable
    return true;
}

/// Calibrate the timer against the clock (20 ms window) and start it in
/// periodic mode at `hz`. Call with interrupts still disabled or enabled alike.
bool lapicTimerStart(uint hz) @nogc nothrow
{
    if (!lapicReady || hz == 0)
        return false;

    lapicWrite(LAPIC_TIMER_DIV, 0x3);                           // divide by 16
    lapicWrite(LAPIC_LVT_TIMER, LVT_MASKED | VEC_TIMER);
    lapicWrite(LAPIC_TIMER_INIT, 0xFFFFFFFF);
    clockDelayMs(20);
    uint cur = lapicRead(LAPIC_TIMER_CUR);
    lapicWrite(LAPIC_TIMER_INIT, 0);

    uint elapsed = 0xFFFFFFFFu - cur;
    lapicTimerFreq = cast(ulong)elapsed * 50;                   // 20 ms -> per second
    ulong count = lapicTimerFreq / hz;
    if (count == 0 || count > 0xFFFFFFFFUL)
        return false;

    lapicWrite(LAPIC_LVT_TIMER, LVT_PERIODIC | VEC_TIMER);
    lapicWrite(LAPIC_TIMER_DIV, 0x3);
    lapicWrite(LAPIC_TIMER_INIT, cast(uint)count);
    return true;
}

module dios.core.clock;

/**
 * Time keeping. Replaces the PIT-based pitTimeTicks().
 *
 *  - Monotonic nanosecond clock: the HPET main counter (ACPI HPET table).
 *    If the machine has no HPET we fall back to the PIT, exactly like the old
 *    code did (and keep it fed from the tick interrupt, so its 16-bit counter
 *    cannot silently wrap twice between two reads).
 *  - A 1 kHz heartbeat from the LAPIC timer. It wakes the main loop out of HLT
 *    and is the future scheduler tick. See lapic.d for how it is calibrated -
 *    against this clock.
 */
import core.volatile;
import dios.core.acpi;
import dios.core.cpu;
import dios.core.idt;
import dios.core.lapic;
import dios.core.pit;
import dios.core.stdio;
import dios.core.vmem;

enum ulong NS_PER_SEC = 1_000_000_000UL;
enum uint TICK_HZ = 1000;

enum : uint
{
    HPET_REG_CAPS    = 0x00,
    HPET_REG_CONFIG  = 0x10,
    HPET_REG_COUNTER = 0xF0
}

__gshared ubyte* hpetRegs;
__gshared bool hpetOk;
__gshared bool hpet64;
__gshared ulong hpetFreq;       // Hz
__gshared ulong hpetHigh;       // upper half for 32-bit counters
__gshared uint hpetLast;

__gshared ulong tickCount;      // LAPIC timer interrupts since start (1 per ms)
__gshared bool tickRunning;

extern(C):

uint hpetRd32(uint off) @nogc nothrow
{
    return volatileLoad(cast(uint*)(hpetRegs + off));
}

void hpetWr32(uint off, uint v) @nogc nothrow
{
    volatileStore(cast(uint*)(hpetRegs + off), v);
}

// Tick count -> nanoseconds without overflowing 64 bits (ticks * 1e9 would after hours).
ulong clockTicksToNs(ulong ticks, ulong freq) @nogc nothrow
{
    ulong sec = ticks / freq;
    ulong rem = ticks % freq;
    return sec * NS_PER_SEC + (rem * NS_PER_SEC) / freq;
}

ulong hpetReadTicks() @nogc nothrow
{
    if (hpet64)
    {
        // Two 32-bit reads with a retry: some chipsets get 64-bit HPET reads wrong.
        uint hi, lo, hi2;
        do
        {
            hi = hpetRd32(HPET_REG_COUNTER + 4);
            lo = hpetRd32(HPET_REG_COUNTER);
            hi2 = hpetRd32(HPET_REG_COUNTER + 4);
        }
        while (hi != hi2);
        return (cast(ulong)hi << 32) | lo;
    }

    // 32-bit counter (wraps every few minutes): extend it in software. Needs to
    // be called at least that often - the 1 kHz tick takes care of that.
    ulong flags = cpuIrqSave();
    uint lo = hpetRd32(HPET_REG_COUNTER);
    if (lo < hpetLast)
        hpetHigh += 1UL << 32;
    hpetLast = lo;
    ulong t = hpetHigh | lo;
    cpuIrqRestore(flags);
    return t;
}

/// Monotonic time since boot in nanoseconds.
ulong clockNowNs() @nogc nothrow
{
    if (hpetOk)
        return clockTicksToNs(hpetReadTicks(), hpetFreq);

    ulong flags = cpuIrqSave();         // pitTimeTicks() keeps state; the tick IRQ calls it too
    ulong t = pitTimeTicks();
    cpuIrqRestore(flags);
    return clockTicksToNs(t, PIT_FREQUENCY);
}

ulong clockNowUs() @nogc nothrow
{
    return clockNowNs() / 1000;
}

/// Absolute deadline `ms` milliseconds from now, in clockNowNs() units.
ulong clockDeadlineMs(uint ms) @nogc nothrow
{
    return clockNowNs() + cast(ulong)ms * 1_000_000UL;
}

void clockDelayUs(uint us) @nogc nothrow
{
    ulong target = clockNowNs() + cast(ulong)us * 1000UL;
    while (clockNowNs() < target) {}
}

void clockDelayMs(uint ms) @nogc nothrow
{
    clockDelayUs(ms * 1000);
}

/// Milliseconds counted by the timer interrupt (0 until clockStartTick succeeds).
ulong clockTickMs() @nogc nothrow
{
    return volatileLoad(&tickCount);
}

bool clockHasHpet() @nogc nothrow
{
    return hpetOk;
}

bool clockTickActive() @nogc nothrow
{
    return tickRunning;
}

/// Bring up the clock source. Needs acpiInit() and vmemInit() to have run.
void clockInit() @nogc nothrow
{
    hpetOk = false;

    if (acpi.hpetFound)
    {
        hpetRegs = cast(ubyte*)vmemMapMMIO(acpi.hpetAddr, 1024);
        if (hpetRegs !is null)
        {
            uint capLow = hpetRd32(HPET_REG_CAPS);
            uint period = hpetRd32(HPET_REG_CAPS + 4);      // femtoseconds per tick
            // Spec: period <= 100 ns (0x05F5E100 fs); 0 or all-ones means a broken device.
            if (period != 0 && period <= 100_000_000 && period != 0xFFFFFFFF)
            {
                hpet64 = (capLow & (1u << 13)) != 0;
                hpetFreq = 1_000_000_000_000_000UL / period;
                // ENABLE_CNF on, LEG_RT_CNF off (we do not want IRQ0/IRQ8 stolen by timer 0/1)
                hpetWr32(HPET_REG_CONFIG, (hpetRd32(HPET_REG_CONFIG) & ~2u) | 1u);
                hpetHigh = 0;
                hpetLast = hpetRd32(HPET_REG_COUNTER);
                hpetOk = true;
            }
        }
    }

    if (!hpetOk)
        pitInit();
}

extern(C) void clockTimerIrq(InterruptFrame* f) @nogc nothrow
{
    volatileStore(&tickCount, tickCount + 1);
    // Keep the clock sources' wrap tracking fed even if nobody is reading them.
    if (!hpetOk || !hpet64)
        clockNowNs();
}

/// Start the 1 kHz LAPIC timer interrupt. Needs lapicInit() and clockInit().
bool clockStartTick() @nogc nothrow
{
    irqRegister(VEC_TIMER, &clockTimerIrq);
    tickRunning = lapicTimerStart(TICK_HZ);
    return tickRunning;
}

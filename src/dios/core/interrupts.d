module dios.core.interrupts;

/**
 * Brings up the modern interrupt stack, in dependency order, and degrades
 * gracefully when a piece is missing:
 *
 *   interruptsEarlyInit()   GDT + TSS + IDT (CPU exceptions -> register dump).
 *                           Needs nothing but the console. Call as early as possible.
 *   interruptsInit()        ACPI -> clock (HPET) -> legacy PIC off -> LAPIC ->
 *                           IOAPIC -> 1 kHz tick. Needs vmemInit() (MMIO mappings).
 */
import dios.core.acpi;
import dios.core.clock;
import dios.core.cpu;
import dios.core.gdt;
import dios.core.idt;
import dios.core.ioapic;
import dios.core.lapic;
import dios.core.pic;
import dios.core.stdio;

struct InterruptStatus
{
    bool acpi;          // MADT found and parsed
    bool lapic;
    bool x2apic;
    bool ioapic;
    bool tick;          // the 1 kHz timer interrupt is running (safe to HLT in the main loop)
    bool hpet;
    uint apicId;
    uint cpuCount;
    uint numIoapics;
}

__gshared InterruptStatus interruptStatus;

extern(C):

void interruptsEarlyInit() @nogc nothrow
{
    gdtInit();
    idtInit();
}

void interruptsInit(ulong hhdmOffset) @nogc nothrow
{
    interruptStatus = InterruptStatus.init;

    interruptStatus.acpi = acpiInit(hhdmOffset);
    interruptStatus.cpuCount = acpi.cpuCount;

    // Time comes first: the LAPIC timer is calibrated against it.
    clockInit();
    interruptStatus.hpet = clockHasHpet();

    // The 8259s must be quiet before we turn the APIC on.
    picDisable();

    if (!lapicInit())
        return;
    interruptStatus.lapic = true;
    interruptStatus.x2apic = lapicX2;
    interruptStatus.apicId = lapicId();

    interruptStatus.ioapic = ioapicInit();
    interruptStatus.numIoapics = numIoapics;

    interruptStatus.tick = clockStartTick();

    // Interrupts on. Everything an ISR touches is set up by now; device
    // drivers register their own handlers later (from this thread of control).
    cpuSti();
}

void interruptsPrintStatus() @nogc nothrow
{
    if (interruptStatus.lapic)
    {
        kprintf("Interrupts: %s id %u, %u CPU(s) in MADT, %u I/O APIC(s)\n",
            interruptStatus.x2apic ? "x2APIC".ptr : "xAPIC".ptr, interruptStatus.apicId,
            interruptStatus.cpuCount, interruptStatus.numIoapics);
    }
    else
    {
        kprintf("Interrupts: no usable local APIC, staying in polled mode\n");
    }

    if (!interruptStatus.acpi)
        kprintf("ACPI: no MADT (is the bootloader providing the RSDP?)\n");

    if (interruptStatus.hpet)
        kprintf("Clock: HPET %llu Hz\n", hpetFreq);
    else
        kprintf("Clock: PIT fallback (no HPET)\n");

    if (interruptStatus.tick)
        kprintf("Tick: %u Hz LAPIC timer (timer %llu Hz)\n", TICK_HZ, lapicTimerFreq);
    else
        kprintf("Tick: off\n");
}

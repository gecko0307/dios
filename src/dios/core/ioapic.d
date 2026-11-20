module dios.core.ioapic;

/**
 * I/O APIC: routes device interrupt lines (global system interrupts, GSIs)
 * to a vector on a CPU's local APIC. Layout comes from the ACPI MADT.
 *
 * Registers are indirect: write the register number to IOREGSEL (+0x00), then
 * access IOWIN (+0x10). Redirection entry n is registers 0x10+2n (low dword)
 * and 0x11+2n (high dword; destination APIC id in bits 24-31).
 */
import core.volatile;
import dios.core.acpi;
import dios.core.stdio;
import dios.core.vmem;

enum uint IOAPIC_REG_VER = 0x01;
enum uint IOAPIC_REDIR_BASE = 0x10;

enum uint REDIR_MASKED      = 1u << 16;
enum uint REDIR_LEVEL       = 1u << 15;
enum uint REDIR_ACTIVE_LOW  = 1u << 13;

struct IoApic
{
    ubyte* regs;
    uint gsiBase;
    uint numPins;
}

__gshared IoApic[ACPI_MAX_IOAPICS] ioapics;
__gshared uint numIoapics;

extern(C):

uint ioapicRead(IoApic* io, uint reg) @nogc nothrow
{
    volatileStore(cast(uint*)io.regs, reg);
    return volatileLoad(cast(uint*)(io.regs + 0x10));
}

void ioapicWrite(IoApic* io, uint reg, uint value) @nogc nothrow
{
    volatileStore(cast(uint*)io.regs, reg);
    volatileStore(cast(uint*)(io.regs + 0x10), value);
}

/// Map every I/O APIC from the MADT and mask all of its pins.
bool ioapicInit() @nogc nothrow
{
    numIoapics = 0;
    for (uint i = 0; i < acpi.numIoApics; i++)
    {
        IoApic* io = &ioapics[numIoapics];
        io.regs = cast(ubyte*)vmemMapMMIO(acpi.ioapics[i].addr, 4096);
        if (io.regs is null)
            continue;
        io.gsiBase = acpi.ioapics[i].gsiBase;
        io.numPins = ((ioapicRead(io, IOAPIC_REG_VER) >> 16) & 0xFF) + 1;
        for (uint pin = 0; pin < io.numPins; pin++)
            ioapicWrite(io, IOAPIC_REDIR_BASE + pin * 2, REDIR_MASKED);
        numIoapics++;
    }
    return numIoapics != 0;
}

IoApic* ioapicForGsi(uint gsi) @nogc nothrow
{
    for (uint i = 0; i < numIoapics; i++)
        if (gsi >= ioapics[i].gsiBase && gsi < ioapics[i].gsiBase + ioapics[i].numPins)
            return &ioapics[i];
    return null;
}

/// Deliver GSI `gsi` to `vector` on the CPU with local APIC id `destApicId`
/// (physical destination, fixed delivery). Writes the high dword first so the
/// entry is complete when the low dword unmasks it.
bool ioapicRoute(uint gsi, uint vector, bool activeLow, bool levelTriggered, uint destApicId) @nogc nothrow
{
    IoApic* io = ioapicForGsi(gsi);
    if (io is null || destApicId > 0xFF)
        return false;
    uint pin = gsi - io.gsiBase;
    uint low = vector & 0xFF;
    if (activeLow)
        low |= REDIR_ACTIVE_LOW;
    if (levelTriggered)
        low |= REDIR_LEVEL;
    ioapicWrite(io, IOAPIC_REDIR_BASE + pin * 2 + 1, destApicId << 24);
    ioapicWrite(io, IOAPIC_REDIR_BASE + pin * 2, low);
    return true;
}

/// Route a legacy ISA IRQ (PS/2 keyboard = 1, PS/2 mouse = 12, ...) honouring
/// the firmware's interrupt source overrides. Returns the GSI used, or -1.
int ioapicRouteIsa(ubyte irq, uint vector, uint destApicId) @nogc nothrow
{
    uint gsi;
    bool low, level;
    acpiIsaIrq(irq, &gsi, &low, &level);
    if (!ioapicRoute(gsi, vector, low, level, destApicId))
        return -1;
    return cast(int)gsi;
}

void ioapicMask(uint gsi) @nogc nothrow
{
    IoApic* io = ioapicForGsi(gsi);
    if (io is null)
        return;
    uint reg = IOAPIC_REDIR_BASE + (gsi - io.gsiBase) * 2;
    ioapicWrite(io, reg, ioapicRead(io, reg) | REDIR_MASKED);
}

module dios.core.acpi;

/**
 * Minimal ACPI table reader: RSDP -> XSDT/RSDT -> MADT (interrupt controller
 * layout) and HPET (high precision timer). No AML interpreter - we only need
 * static tables.
 *
 * Every table is mapped explicitly (read-only, write-back like the HHDM) instead
 * of assuming the bootloader's HHDM covers firmware regions. The mappings are
 * never freed - there are a handful of tables and virtual space is plentiful.
 * Everything in the tables is little-endian and not necessarily aligned, so
 * fields are read byte-wise.
 */
import dios.bootloader.limine;
import dios.core.stdio;
import dios.core.vmem;

enum uint ACPI_MAX_IOAPICS = 8;
enum uint ACPI_MAX_ISOS    = 32;

struct AcpiIoApic
{
    ubyte id;
    uint addr;
    uint gsiBase;
}

// Interrupt Source Override: ISA IRQ `source` is wired to global system interrupt `gsi`.
struct AcpiIso
{
    ubyte source;
    uint gsi;
    ushort flags;   // bits 0-1 polarity, bits 2-3 trigger (0 = bus default)
}

struct AcpiInfo
{
    bool valid;
    bool madtFound;
    bool hpetFound;
    bool pcatCompat;        // dual 8259 present
    ulong lapicAddr;
    uint cpuCount;          // enabled / online-capable processors
    uint numIoApics;
    AcpiIoApic[ACPI_MAX_IOAPICS] ioapics;
    uint numIsos;
    AcpiIso[ACPI_MAX_ISOS] isos;
    ulong hpetAddr;
}

__gshared AcpiInfo acpi;

extern(C):

ubyte acpiRd8(const(ubyte)* p, size_t off) @nogc nothrow
{
    return p[off];
}

ushort acpiRd16(const(ubyte)* p, size_t off) @nogc nothrow
{
    return cast(ushort)(p[off] | (p[off + 1] << 8));
}

uint acpiRd32(const(ubyte)* p, size_t off) @nogc nothrow
{
    return cast(uint)p[off] | (cast(uint)p[off + 1] << 8) |
           (cast(uint)p[off + 2] << 16) | (cast(uint)p[off + 3] << 24);
}

ulong acpiRd64(const(ubyte)* p, size_t off) @nogc nothrow
{
    return cast(ulong)acpiRd32(p, off) | (cast(ulong)acpiRd32(p, off + 4) << 32);
}

bool acpiSigEq(const(ubyte)* p, string sig) @nogc nothrow
{
    for (size_t i = 0; i < sig.length; i++)
        if (p[i] != cast(ubyte)sig[i])
            return false;
    return true;
}

bool acpiChecksumOk(const(ubyte)* p, size_t len) @nogc nothrow
{
    ubyte sum = 0;
    for (size_t i = 0; i < len; i++)
        sum = cast(ubyte)(sum + p[i]);
    return sum == 0;
}

// Map `len` bytes of physical memory for reading. Null if the mapping fails.
const(ubyte)* acpiMap(ulong phys, size_t len) @nogc nothrow
{
    return cast(const(ubyte)*)vmemMapMMIO(phys, len, PTE_PRESENT);
}

// Map a system description table: header first to learn its length, then all of it.
const(ubyte)* acpiMapTable(ulong phys, uint* outLen, uint maxLen) @nogc nothrow
{
    const(ubyte)* hdr = acpiMap(phys, 36);
    if (hdr is null)
        return null;
    uint len = acpiRd32(hdr, 4);
    if (len < 36 || len > maxLen)
        return null;
    *outLen = len;
    return acpiMap(phys, len);
}

void acpiParseMadt(const(ubyte)* t, uint len) @nogc nothrow
{
    acpi.madtFound = true;
    acpi.lapicAddr = acpiRd32(t, 36);
    acpi.pcatCompat = (acpiRd32(t, 40) & 1) != 0;

    uint off = 44;
    while (off + 2 <= len)
    {
        ubyte type = t[off];
        ubyte elen = t[off + 1];
        if (elen < 2 || off + elen > len)
            break;

        if (type == 0 && elen >= 8)                 // processor local APIC
        {
            if (acpiRd32(t, off + 4) & 3)           // enabled | online capable
                acpi.cpuCount++;
        }
        else if (type == 9 && elen >= 16)           // processor local x2APIC
        {
            if (acpiRd32(t, off + 8) & 3)
                acpi.cpuCount++;
        }
        else if (type == 1 && elen >= 12)           // I/O APIC
        {
            if (acpi.numIoApics < ACPI_MAX_IOAPICS)
            {
                AcpiIoApic* io = &acpi.ioapics[acpi.numIoApics++];
                io.id = t[off + 2];
                io.addr = acpiRd32(t, off + 4);
                io.gsiBase = acpiRd32(t, off + 8);
            }
        }
        else if (type == 2 && elen >= 10)           // interrupt source override
        {
            if (t[off + 2] == 0 && acpi.numIsos < ACPI_MAX_ISOS)    // bus 0 = ISA
            {
                AcpiIso* iso = &acpi.isos[acpi.numIsos++];
                iso.source = t[off + 3];
                iso.gsi = acpiRd32(t, off + 4);
                iso.flags = acpiRd16(t, off + 8);
            }
        }
        else if (type == 5 && elen >= 12)           // local APIC address override
        {
            acpi.lapicAddr = acpiRd64(t, off + 4);
        }

        off += elen;
    }
}

void acpiParseHpet(const(ubyte)* t, uint len) @nogc nothrow
{
    if (len < 56)
        return;
    // Generic Address Structure at offset 40: [space id][width][offset][access][address:8]
    if (t[40] != 0)                // 0 = system memory; I/O-space HPETs do not exist in practice
        return;
    ulong addr = acpiRd64(t, 44);
    if (addr == 0)
        return;
    acpi.hpetFound = true;
    acpi.hpetAddr = addr;
}

bool acpiInit(ulong hhdmOffset) @nogc nothrow
{
    acpi = AcpiInfo.init;

    if (rsdpRequest.response is null || rsdpRequest.response.address is null)
        return false;

    // Base revision 3 hands out a physical address, older revisions a virtual one.
    ulong raw = cast(ulong)rsdpRequest.response.address;
    ulong rsdpPhys = (raw >= hhdmOffset) ? raw - hhdmOffset : raw;
    const(ubyte)* rsdp = acpiMap(rsdpPhys, 36);
    if (rsdp is null)
        return false;

    if (!acpiSigEq(rsdp, "RSD PTR ") || !acpiChecksumOk(rsdp, 20))
        return false;

    ubyte revision = rsdp[15];
    ulong rootPhys;
    uint entrySize;
    uint rsdpLen = acpiRd32(rsdp, 20);
    bool extendedOk = revision >= 2 && rsdpLen == 36 &&
                      acpiChecksumOk(rsdp, rsdpLen);
    if (extendedOk && acpiRd64(rsdp, 24) != 0)
    {
        rootPhys = acpiRd64(rsdp, 24);      // XSDT
        entrySize = 8;
    }
    else
    {
        rootPhys = acpiRd32(rsdp, 16);      // RSDT
        entrySize = 4;
    }
    if (rootPhys == 0)
        return false;

    uint rootLen;
    const(ubyte)* root = acpiMapTable(rootPhys, &rootLen, 1u << 20);
    if (root is null || !acpiSigEq(root, entrySize == 8 ? "XSDT" : "RSDT"))
        return false;

    uint count = (rootLen - 36) / entrySize;
    for (uint i = 0; i < count; i++)
    {
        ulong tablePhys = (entrySize == 8) ? acpiRd64(root, 36 + i * 8) : acpiRd32(root, 36 + i * 4);
        if (tablePhys == 0)
            continue;

        // Peek at the signature first: most tables (DSDT, SSDT, ...) are big and of no interest.
        const(ubyte)* hdr = acpiMap(tablePhys, 36);
        if (hdr is null)
            continue;
        bool isMadt = acpiSigEq(hdr, "APIC");
        bool isHpet = acpiSigEq(hdr, "HPET");
        if (!isMadt && !isHpet)
            continue;

        uint len;
        const(ubyte)* t = acpiMapTable(tablePhys, &len, 1u << 20);
        if (t is null || !acpiChecksumOk(t, len))
            continue;

        if (isMadt)
            acpiParseMadt(t, len);
        else
            acpiParseHpet(t, len);
    }

    acpi.valid = acpi.madtFound;
    return acpi.valid;
}

/// Where does legacy ISA IRQ `irq` end up? Applies Interrupt Source Overrides.
/// Defaults for ISA: same GSI number, active high, edge triggered.
void acpiIsaIrq(ubyte irq, uint* gsi, bool* activeLow, bool* levelTriggered) @nogc nothrow
{
    *gsi = irq;
    *activeLow = false;
    *levelTriggered = false;
    for (uint i = 0; i < acpi.numIsos; i++)
    {
        if (acpi.isos[i].source == irq)
        {
            ushort fl = acpi.isos[i].flags;
            *gsi = acpi.isos[i].gsi;
            *activeLow = (fl & 3) == 3;
            *levelTriggered = ((fl >> 2) & 3) == 3;
            return;
        }
    }
}

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
import dios.core.cpu;
import dios.core.port;

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

enum uint ACPI_MAX_TABLES = 40;

// One entry of the RSDT/XSDT, cached for the `acpi` shell command.
struct AcpiTableRef
{
    char[4] sig;
    ubyte revision;
    uint length;
    ulong phys;
}

struct AcpiInfo
{
    bool valid;
    ubyte rsdpRevision;
    bool rootIsXsdt;
    uint numTables;
    AcpiTableRef[ACPI_MAX_TABLES] tables;
    bool resetSupported;    // FADT RESET_REG usable
    ubyte resetSpace;       // address space: 0 memory, 1 I/O, 2 PCI config
    ulong resetAddr;
    ubyte resetValue;
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
    bool fadtFound;
    bool s5Found;
    ushort pm1aControlPort;
    ushort pm1bControlPort;
    ubyte pm1ControlLength;
    ubyte sleepTypeA;
    ubyte sleepTypeB;
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

// Decode an AML PkgLength. `offset` points to its lead byte.
bool acpiAmlPkgLength(const(ubyte)* aml, uint amlLen, uint offset,
                      uint* value, uint* encodedBytes) @nogc nothrow
{
    if (offset >= amlLen)
        return false;

    ubyte lead = aml[offset];
    uint follow = lead >> 6;
    uint length;
    if (follow == 0)
    {
        length = lead & 0x3F;
    }
    else
    {
        length = lead & 0x0F;
        if (offset + follow >= amlLen)
            return false;
        for (uint i = 0; i < follow; i++)
            length |= cast(uint)aml[offset + 1 + i] << (4 + i * 8);
    }

    *value = length;
    *encodedBytes = follow + 1;
    return true;
}

// Read the small integer encodings used by the standard _S5_ package.
bool acpiAmlInteger(const(ubyte)* aml, uint amlLen, uint* offset,
                    ubyte* value) @nogc nothrow
{
    if (*offset >= amlLen)
        return false;

    ubyte op = aml[*offset];
    (*offset)++;
    if (op == 0x00) // ZeroOp
    {
        *value = 0;
        return true;
    }
    if (op == 0x01) // OneOp
    {
        *value = 1;
        return true;
    }
    if (op == 0x0A) // BytePrefix
    {
        if (*offset + 1 > amlLen) return false;
        *value = aml[*offset];
        (*offset)++;
        return true;
    }
    if (op == 0x0B) // WordPrefix
    {
        if (*offset + 2 > amlLen) return false;
        *value = cast(ubyte)acpiRd16(aml, *offset);
        *offset += 2;
        return true;
    }
    if (op == 0x0C) // DWordPrefix
    {
        if (*offset + 4 > amlLen) return false;
        *value = cast(ubyte)acpiRd32(aml, *offset);
        *offset += 4;
        return true;
    }
    if (op == 0x0E) // QWordPrefix
    {
        if (*offset + 8 > amlLen) return false;
        *value = cast(ubyte)acpiRd64(aml, *offset);
        *offset += 8;
        return true;
    }
    return false;
}

// This is deliberately not a general AML interpreter. It recognizes the
// conventional Name (_S5_, Package (...) { SleepTypeA, SleepTypeB, ... }).
bool acpiFindS5(const(ubyte)* dsdt, uint len, ubyte* typeA, ubyte* typeB) @nogc nothrow
{
    if (len < 8)
        return false;

    for (uint i = 36; i + 7 < len; i++)
    {
        if (dsdt[i] != 0x08 || dsdt[i + 1] != '_' ||
            dsdt[i + 2] != 'S' || dsdt[i + 3] != '5' || dsdt[i + 4] != '_')
            continue;

        uint pkgOp = i + 5;
        if (dsdt[pkgOp] != 0x12)
            continue;

        uint pkgLen;
        uint pkgLenBytes;
        if (!acpiAmlPkgLength(dsdt, len, pkgOp + 1, &pkgLen, &pkgLenBytes))
            continue;

        uint pkgStart = pkgOp + 1;
        uint pkgEnd = pkgStart + pkgLen;
        uint cursor = pkgStart + pkgLenBytes;
        if (pkgEnd > len || cursor >= pkgEnd)
            continue;

        ubyte elements = dsdt[cursor++];
        if (elements < 2)
            continue;

        ubyte a, b;
        if (!acpiAmlInteger(dsdt, pkgEnd, &cursor, &a) ||
            !acpiAmlInteger(dsdt, pkgEnd, &cursor, &b))
            continue;

        *typeA = a;
        *typeB = b;
        return true;
    }
    return false;
}

void acpiParseFadt(const(ubyte)* t, uint len) @nogc nothrow
{
    if (len < 90)
        return;

    acpi.fadtFound = true;

    // RESET_REG (GAS at 116) and RESET_VALUE (128); FLAGS bit 10 = RESET_REG_SUP.
    if (len >= 129 && (acpiRd32(t, 112) & (1u << 10)) != 0)
    {
        acpi.resetSpace = t[116];
        acpi.resetAddr = acpiRd64(t, 120);
        acpi.resetValue = t[128];
        acpi.resetSupported = (acpi.resetSpace == 0 || acpi.resetSpace == 1) && acpi.resetAddr != 0;
    }
    ulong dsdtPhys = acpiRd32(t, 40);
    if (len >= 148)
    {
        ulong xDsdt = acpiRd64(t, 140);
        if (xDsdt != 0)
            dsdtPhys = xDsdt;
    }

    // Prefer the legacy PM1 control blocks. They are I/O ports on conventional
    // x86 PCs and are sufficient for the first DIOS power-management path.
    uint pm1a = acpiRd32(t, 64);
    uint pm1b = acpiRd32(t, 68);
    acpi.pm1ControlLength = t[89];

    // If legacy fields are absent, accept the extended GAS only when it names
    // System I/O space. FADT X_PM1x_CNT_BLK offsets are 172 and 184.
    if (pm1a == 0 && len >= 184 && t[172] == 1)
    {
        ulong addr = acpiRd64(t, 176);
        if (addr <= 0xFFFF)
        {
            pm1a = cast(uint)addr;
            if (acpi.pm1ControlLength == 0)
                acpi.pm1ControlLength = cast(ubyte)((t[173] + 7) / 8);
        }
    }
    if (pm1b == 0 && len >= 196 && t[184] == 1)
    {
        ulong addr = acpiRd64(t, 188);
        if (addr <= 0xFFFF)
        {
            pm1b = cast(uint)addr;
            if (acpi.pm1ControlLength == 0)
                acpi.pm1ControlLength = cast(ubyte)((t[185] + 7) / 8);
        }
    }

    if (pm1a <= 0xFFFF)
        acpi.pm1aControlPort = cast(ushort)pm1a;
    if (pm1b <= 0xFFFF)
        acpi.pm1bControlPort = cast(ushort)pm1b;

    if (dsdtPhys == 0)
        return;

    uint dsdtLen;
    const(ubyte)* dsdt = acpiMapTable(dsdtPhys, &dsdtLen, 1u << 20);
    if (dsdt is null || !acpiSigEq(dsdt, "DSDT") || !acpiChecksumOk(dsdt, dsdtLen))
        return;

    acpi.s5Found = acpiFindS5(dsdt, dsdtLen, &acpi.sleepTypeA, &acpi.sleepTypeB);
}

/// Pulse the FADT reset register. Returns false if the firmware does not offer
/// one; on success the machine normally resets before this returns.
bool acpiReset() @nogc nothrow
{
    if (!acpi.resetSupported)
        return false;
    if (acpi.resetSpace == 1)
    {
        if (acpi.resetAddr > 0xFFFF)
            return false;
        kPortWriteByte(cast(ushort)acpi.resetAddr, acpi.resetValue);
        return true;
    }
    // Memory-mapped register.
    ubyte* reg = cast(ubyte*)vmemMapMMIO(acpi.resetAddr, 1, PTE_PRESENT | PTE_RW | PTE_PCD);
    if (reg is null)
        return false;
    *reg = acpi.resetValue;
    return true;
}

/// Request ACPI S5 (soft power-off). Returns false if firmware data is absent.
/// A successful request normally powers the machine off before this returns.
bool acpiPoweroff() @nogc nothrow
{
    if (!acpi.s5Found || acpi.pm1aControlPort == 0 || acpi.pm1ControlLength < 2)
        return false;

    // SLP_TYP is bits 10..12 and SLP_EN is bit 13 in PM1 control registers.
    // Preserve all unrelated control bits.
    cpuCli();
    ushort controlA = kPortRead16(acpi.pm1aControlPort);
    controlA = cast(ushort)((controlA & ~((7u << 10) | (1u << 13))) |
                            ((acpi.sleepTypeA & 7u) << 10));
    kPortWrite16(acpi.pm1aControlPort, controlA);

    // Program PM1b first as well, but do not set SLP_EN there. ACPI requires
    // the sleep type to be written before the enable bit is asserted in PM1a.
    if (acpi.pm1bControlPort != 0)
    {
        ushort controlB = kPortRead16(acpi.pm1bControlPort);
        controlB = cast(ushort)((controlB & ~((7u << 10) | (1u << 13))) |
                                ((acpi.sleepTypeB & 7u) << 10));
        kPortWrite16(acpi.pm1bControlPort, controlB);
    }

    kPortWrite16(acpi.pm1aControlPort, cast(ushort)(controlA | (1u << 13)));

    // If firmware/hardware did not power off, remain halted rather than
    // returning to a shell that has already requested shutdown.
    for (;;)
        asm @nogc nothrow { hlt; }
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
    acpi.rsdpRevision = revision;
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

    acpi.rootIsXsdt = entrySize == 8;
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
        if (acpi.numTables < ACPI_MAX_TABLES)
        {
            AcpiTableRef* r = &acpi.tables[acpi.numTables++];
            for (uint k = 0; k < 4; k++)
                r.sig[k] = cast(char)hdr[k];
            r.length = acpiRd32(hdr, 4);
            r.revision = hdr[8];
            r.phys = tablePhys;
        }
        bool isMadt = acpiSigEq(hdr, "APIC");
        bool isHpet = acpiSigEq(hdr, "HPET");
        bool isFadt = acpiSigEq(hdr, "FACP");
        if (!isMadt && !isHpet && !isFadt)
            continue;

        uint len;
        const(ubyte)* t = acpiMapTable(tablePhys, &len, 1u << 20);
        if (t is null || !acpiChecksumOk(t, len))
            continue;

        if (isMadt)
            acpiParseMadt(t, len);
        else if (isHpet)
            acpiParseHpet(t, len);
        else
            acpiParseFadt(t, len);
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

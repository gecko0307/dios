module dios.core.pci;

import dios.core.port;
import dios.core.vmem;
import dios.core.xhci;
import dios.core.stdio;

version(X86_64):

enum PCI_CONFIG_ADDRESS = 0xCF8;
enum PCI_CONFIG_DATA = 0xCFC;

enum ubyte PCI_CONFIG_VENDOR_ID = 0x00;
enum ubyte PCI_CONFIG_DEVICE_ID = 0x02;

enum ubyte PCI_CONFIG_COMMAND = 0x04;
enum ubyte PCI_CONFIG_STATUS = 0x06;

enum ubyte PCI_CONFIG_REVISION = 0x08;
enum ubyte PCI_CONFIG_PROGRAM_INTERFACE = 0x09;

enum ubyte PCI_CONFIG_SUBCLASS = 0x0A;
enum ubyte PCI_CONFIG_CLASS = 0x0B;
enum ubyte PCI_CONFIG_HEADER_TYPE = 0x0E;

enum ubyte PCI_CONFIG_BAR0 = 0x10;
enum ubyte PCI_CONFIG_BAR1 = 0x14;

enum ushort PCI_CMD_IO = 0x1;
enum ushort PCI_CMD_MEMORY = 0x2;
enum ushort PCI_CMD_BUSMASTER = 0x4;

__gshared bool xhciFound = false;

extern(C):

uint pciConfigRead32(uint bus, uint device, uint func, ubyte offset) @nogc nothrow
{
    uint addr = 0x80000000 | (bus << 16) | (device << 11) | (func << 8) | (offset & 0xFC);
    kPortWrite32(PCI_CONFIG_ADDRESS, addr);
    return kPortRead32(PCI_CONFIG_DATA);
}

void pciConfigWrite32(uint bus, uint device, uint func, ubyte offset, uint value) @nogc nothrow
{
    uint addr = 0x80000000 | (bus << 16) | (device << 11) | (func << 8) | (offset & 0xFC);
    kPortWrite32(PCI_CONFIG_ADDRESS, addr);
    kPortWrite32(PCI_CONFIG_DATA, value);
}

// Read-modify-write on the whole dword. The old version wrote only the LOW
// 16 bits of the address to port 0xCF8 (the enable bit and bus number live in
// the high half), so it only worked if the previous access had hit the same
// device by luck.
void pciConfigWrite16(uint bus, uint device, uint func, ubyte offset, ushort value) @nogc nothrow
{
    uint old = pciConfigRead32(bus, device, func, offset & 0xFC);
    uint shift = (offset & 2) * 8;
    uint nv = (old & ~(0xFFFFu << shift)) | (cast(uint)value << shift);
    // Dword 0x04 = Command (low) + Status (high). Status bits are
    // write-1-to-clear, so never write back the status bits we just read.
    if ((offset & 0xFC) == PCI_CONFIG_COMMAND)
        nv &= 0x0000FFFF;
    pciConfigWrite32(bus, device, func, offset & 0xFC, nv);
}

ushort pciConfigRead16(uint bus, uint device, uint func, ubyte offset) @nogc nothrow
{
    uint data = pciConfigRead32(bus, device, func, offset & 0xFC);
    return cast(ushort)((data >> ((offset & 2) * 8)) & 0xFFFF);
}

ubyte pciConfigRead8(uint bus, uint device, uint func, ubyte offset) @nogc nothrow
{
    uint data = pciConfigRead32(bus, device, func, offset & 0xFC);
    return cast(ubyte)((data >> ((offset & 3) * 8)) & 0xFF);
}

ushort pciReadVendorID(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead16(bus, device, func, PCI_CONFIG_VENDOR_ID);
}

ushort pciReadDeviceID(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead16(bus, device, func, PCI_CONFIG_DEVICE_ID);
}

ubyte pciReadHeaderType(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, PCI_CONFIG_HEADER_TYPE);
}

ubyte pciReadClass(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, PCI_CONFIG_CLASS);
}

ubyte pciReadSubclass(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, PCI_CONFIG_SUBCLASS);
}

ubyte pciReadProgIF(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, PCI_CONFIG_PROGRAM_INTERFACE);
}

ushort pciReadCommand(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead16(bus, device, func, PCI_CONFIG_COMMAND);
}

void pciWriteCommand(uint bus, uint device, uint func, ushort value) @nogc nothrow
{
    pciConfigWrite16(bus, device, func, PCI_CONFIG_COMMAND, value);
}

// Find size and physical address of a memory BAR0 (handles 32 and 64-bit BARs).
// Sizing is done with decoding switched OFF; the old code wrote 0xFFFFFFFF
// into the BAR while the device was still decoding memory.
bool pciGetBar0(uint bus, uint device, uint func, ulong* outPhys, ulong* outSize) @nogc nothrow
{
    uint orig0 = pciConfigRead32(bus, device, func, PCI_CONFIG_BAR0);
    if (orig0 & 1)
        return false; // I/O BAR
    bool is64 = ((orig0 >> 1) & 3) == 2;
    uint orig1 = is64 ? pciConfigRead32(bus, device, func, PCI_CONFIG_BAR1) : 0;

    ushort cmd = pciReadCommand(bus, device, func);
    pciWriteCommand(bus, device, func, cast(ushort)(cmd & ~(PCI_CMD_IO | PCI_CMD_MEMORY | PCI_CMD_BUSMASTER)));

    pciConfigWrite32(bus, device, func, PCI_CONFIG_BAR0, 0xFFFFFFFF);
    if (is64)
        pciConfigWrite32(bus, device, func, PCI_CONFIG_BAR1, 0xFFFFFFFF);
    uint s0 = pciConfigRead32(bus, device, func, PCI_CONFIG_BAR0);
    uint s1 = is64 ? pciConfigRead32(bus, device, func, PCI_CONFIG_BAR1) : 0xFFFFFFFF;

    pciConfigWrite32(bus, device, func, PCI_CONFIG_BAR0, orig0);
    if (is64)
        pciConfigWrite32(bus, device, func, PCI_CONFIG_BAR1, orig1);
    pciWriteCommand(bus, device, func, cmd);

    ulong mask = (cast(ulong)s1 << 32) | (s0 & 0xFFFFFFF0);
    ulong size = ~mask + 1;
    ulong phys = (cast(ulong)orig1 << 32) | (orig0 & 0xFFFFFFF0);
    if (phys == 0 || size == 0)
        return false; // firmware never assigned it
    *outPhys = phys;
    *outSize = size;
    return true;
}

void pciCheckFunction(uint bus, uint device, uint func) @nogc nothrow
{
    ushort vendorID = pciReadVendorID(bus, device, func);
    if (vendorID == 0xFFFF)
        return;

    ushort deviceID = pciReadDeviceID(bus, device, func);
    ubyte dClass = pciReadClass(bus, device, func);
    ubyte dSubclass = pciReadSubclass(bus, device, func);

    if (dClass != 0x0C || dSubclass != 0x03)
        return;

    ubyte progIf = pciReadProgIF(bus, device, func);
    string progIfStr;
    if (progIf == 0x00) progIfStr = "UHCI";
    else if (progIf == 0x10) progIfStr = "OHCI";
    else if (progIf == 0x20) progIfStr = "EHCI (USB 2.0)";
    else if (progIf == 0x30) progIfStr = "XHCI (USB 3.0)";
    else progIfStr = "undefined";
    kprintf("USB controller %s @ %u:%u.%u  %x:%x\n", progIfStr.ptr, bus, device, func,
        cast(uint)vendorID, cast(uint)deviceID);

    if (progIf != 0x30 || xhciFound)
        return; // stop once one controller has a mouse

    ulong phys, size;
    if (!pciGetBar0(bus, device, func, &phys, &size))
    {
        kprintf("  no usable BAR0\n");
        return;
    }
    kprintf("  MMIO phys %llx size %llu\n", phys, size);

    // Memory decode + bus mastering (the controller DMAs into our rings).
    pciWriteCommand(bus, device, func,
        cast(ushort)(pciReadCommand(bus, device, func) | PCI_CMD_MEMORY | PCI_CMD_BUSMASTER));

    void* regs = vmemMapMMIO(phys, size);
    if (regs is null)
    {
        kprintf("  could not map MMIO\n");
        return;
    }
    // Machines often have several xHCI controllers (e.g. a Thunderbolt one
    // plus the PCH one with the real USB-A ports). Try each in turn; keep
    // the first one that ends up with a working mouse, stop the others.
    xhciInit(regs);
    if (xhciMouseRunning())
        xhciFound = true;
    else
    {
        kprintf("  no USB mouse on this controller\n");
        xhciShutdown();
    }
}

void pciScan() @nogc nothrow
{
    for (uint bus = 0; bus < 256; bus++)
    {
        for (uint device = 0; device < 32; device++)
        {
            if (pciReadVendorID(bus, device, 0) == 0xFFFF)
                continue;

            // Multi-function devices have bit 7 of the header type set.
            uint numFuncs = (pciReadHeaderType(bus, device, 0) & 0x80) ? 8 : 1;
            for (uint func = 0; func < numFuncs; func++)
                pciCheckFunction(bus, device, func);
        }
    }
}

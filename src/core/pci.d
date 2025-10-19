module core.pci;

import core.port;
import stdio;

version(X86_64):

enum PCI_CONFIG_ADDRESS = 0xCF8;
enum PCI_CONFIG_DATA = 0xCFC;

extern(C):

uint pciConfigRead32(uint bus, uint device, uint func, ubyte offset) @nogc nothrow
{
    uint address = 0x80000000 | (bus << 16) | (device << 11) | (func << 8) | (offset & 0xFC);
    kPortWrite32(PCI_CONFIG_ADDRESS, address);
    return kPortRead32(PCI_CONFIG_DATA);
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
    return pciConfigRead16(bus, device, func, 0x00);
}

ushort pciReadDeviceID(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead16(bus, device, func, 0x02);
}

ubyte pciReadHeaderType(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, 0x0E);
}

ubyte pciReadClass(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, 0x0B);
}

ubyte pciReadSubclass(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, 0x0A);
}

ubyte pciReadProgIF(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead8(bus, device, func, 0x09);
}

ushort pciReadCommand(uint bus, uint device, uint func) @nogc nothrow
{
    return pciConfigRead16(bus, device, func, 0x04);
}

void pciWriteCommand(uint bus, uint device, uint func, ushort value) @nogc nothrow
{
    uint addr = 0x80000000 | (bus << 16) | (device << 11) | (func << 8) | (0x04 & 0xFC);
    kPortWrite32(PCI_CONFIG_ADDRESS, addr);
    kPortWrite32(PCI_CONFIG_DATA, value);
}

void enableMemoryBusMaster(uint bus, uint device, uint func) @nogc nothrow
{
    ushort cmd = pciReadCommand(bus, device, func);
    cmd |= 0x6; // Memory Space (bit1) + Bus Master (bit2)
    pciWriteCommand(bus, device, func, cmd);
}

void pciScan() @nogc nothrow
{
    for (uint bus = 0; bus < 256; bus++)
    {
        for (uint device = 0; device < 32; device++)
        {
            ushort vendorID = pciReadVendorID(bus, device, 0);
            if (vendorID == 0xFFFF)
                continue;
            
            ushort deviceID = pciReadDeviceID(bus, device, 0);
            ubyte headerType = pciReadHeaderType(bus, device, 0);
            ubyte dClass = pciReadClass(bus, device, 0);
            ubyte dSubclass = pciReadSubclass(bus, device, 0);
            
            kprintf("Bus %u, Device %u\n", bus, device);
            kprintf("  VendorID: %x DeviceID: %x\n", vendorID, deviceID);
            kprintf("  Class: %x Subclass: %x HeaderType: %x\n", dClass, dSubclass, headerType);
            
            if ((headerType & 0x80) != 0)
            {
                for (uint func = 1; func < 8; func++)
                {
                    ushort vendorIDf = pciReadVendorID(bus, device, func);
                    if (vendorIDf == 0xFFFF)
                        continue;
                    
                    ushort deviceIDf = pciReadDeviceID(bus, device, func);
                    ubyte classf = pciReadClass(bus, device, func);
                    ubyte subclassf = pciReadSubclass(bus, device, func);
                    
                    kprintf("  Func %u VendorID: %x DeviceID: %x Class: %x Subclass: %x\n",
                        func, vendorIDf, deviceIDf, classf, subclassf);
                }
            }
            else if (dClass == 0x0C && dSubclass == 0x03)
            {
                ubyte progIf = pciReadProgIF(bus, device, 0);
                string progIfStr;
                if (progIf == 0x00) progIfStr = "UHCI";
                else if (progIf == 0x10) progIfStr = "OHCI";
                else if (progIf == 0x20) progIfStr = "EHCI (USB 2.0)";
                else if (progIf == 0x30) progIfStr = "XHCI (USB 3.0)";
                else progIfStr = "undefined";
                kprintf("  USB controller %s\n", progIfStr.ptr);
                
                if (progIf == 0x30)
                {
                    enableMemoryBusMaster(bus, device, 0);
                    uint bar0 = pciConfigRead32(bus, device, 0, 0x10);
                    uint bar1 = pciConfigRead32(bus, device, 0, 0x14);
                    
                    if ((bar0 & 0x1) == 0)
                    {
                        // MMIO
                        if ((bar0 & 0x6) == 0x4)
                        {
                            ulong base = (cast(ulong)bar1 << 32) | (bar0 & 0xFFFFFFF0);
                            kprintf("  MMIO port (64-bit): %llx\n", base);
                        }
                        else
                        {
                            uint base = bar0 & 0xFFFFFFF0;
                            kprintf("  MMIO port (32-bit): %x\n", base);
                        }
                    }
                    else
                    {
                        // IO port
                        uint io_base = bar0 & 0xFFFFFFFC;
                        kprintf("  IO port: %x\n", io_base);
                    }
                }
            }
        }
    }
}

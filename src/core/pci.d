module core.pci;

import core.volatile;
import core.port;
import core.vmem;
import core.xhci;
import stdio;

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
enum ubyte PCI_CONFIG_BAR2 = 0x18;
enum ubyte PCI_CONFIG_BAR3 = 0x1C;
enum ubyte PCI_CONFIG_BAR4 = 0x20;
enum ubyte PCI_CONFIG_BAR5 = 0x24;

extern(C):

uint pciConfigRead32(uint bus, uint device, uint func, ubyte offset) @nogc nothrow
{
    uint address = 0x80000000 | (bus << 16) | (device << 11) | (func << 8) | (offset & 0xFC);
    kPortWrite32(PCI_CONFIG_ADDRESS, address);
    return kPortRead32(PCI_CONFIG_DATA);
}

void pciConfigWrite32(uint bus, uint device, uint func, ubyte offset, uint value) @nogc nothrow
{
    uint addr = 0x80000000 | (bus << 16) | (device << 11) | (func << 8) | (offset & 0xFC);
    kPortWrite32(PCI_CONFIG_ADDRESS, addr);
    kPortWrite32(PCI_CONFIG_DATA, value);
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
    pciConfigWrite32(bus, device, func, PCI_CONFIG_COMMAND, value);
}

struct xhci_cap_regs
{
    uint cap_caplen_version;
    uint cap_hcsparams1;
    uint cap_hcsparams2;
    uint cap_hcsparams3;
    uint cap_hccparams1;
    uint cap_dboff;
    uint cap_rtsoff;
    uint cap_hccparams2;
}

void pciScan(size_t hhdmOffset) @nogc nothrow
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
            
            /*
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
            */
            
            if (dClass == 0x0C && dSubclass == 0x03)
            {
                ubyte progIf = pciReadProgIF(bus, device, 0);
                string progIfStr;
                if (progIf == 0x00) progIfStr = "UHCI";
                else if (progIf == 0x10) progIfStr = "OHCI";
                else if (progIf == 0x20) progIfStr = "EHCI (USB 2.0)";
                else if (progIf == 0x30) progIfStr = "XHCI (USB 3.0)";
                else progIfStr = "undefined";
                kprintf("USB controller %s @ bus %u / device %u\n", progIfStr.ptr, bus, device);
                kprintf("  vendorID: %x, deviceID: %x\n", vendorID, deviceID);
                
                if (progIf == 0x30)
                {
                    ushort cmd = pciReadCommand(bus, device, 0);
                    cmd |= 0x6; // Enable memory I/O and bus master
                    pciWriteCommand(bus, device, 0, cmd);
                    
                    uint bar0 = pciConfigRead32(bus, device, 0, PCI_CONFIG_BAR0) & 0xFFFFFFF0;
                    uint bar1 = pciConfigRead32(bus, device, 0, PCI_CONFIG_BAR1);
                    
                    if ((bar0 & 0x1) == 0)
                    {
                        // MMIO
                        ulong mmio = (cast(ulong)bar1 << 32) | (bar0 & 0xFFFFFFF0);
                        kprintf("  MMIO capability registers phys: %llx\n", mmio);
                        
                        pciConfigWrite32(bus, device, 0, 0x10, 0xFFFFFFFF);
                        pciConfigWrite32(bus, device, 0, 0x14, 0xFFFFFFFF);
                        uint bar0_w = pciConfigRead32(bus, device, 0, 0x10);
                        uint bar1_w = pciConfigRead32(bus, device, 0, 0x14);
                        ulong mask = (cast(ulong)bar1_w << 32) | (bar0_w & 0xFFFFFFF0);
                        ulong barSize = ~mask + 1;
                        pciConfigWrite32(bus, device, 0, 0x10, bar0);
                        pciConfigWrite32(bus, device, 0, 0x14, bar1);

                        kprintf("  BAR size: %llu\n", barSize);

                        void* capsRegs = vmemMapMMIO(mmio, barSize);
                        kprintf("  MMIO capability registers virt: %llx\n", cast(ulong)capsRegs);

                        XHCIDevice xhciDev;
                        xhciDeviceInit(&xhciDev, capsRegs);

                        kprintf("  CAPLENGTH: %u\n", xhciDev.capRegLength);
                        kprintf("  HCIVERSION: %u\n", xhciDev.hciVersion);
                        kprintf("  HCSPARAMS1: %llx\n", xhciDev.structParams1);
                        kprintf("  HCSPARAMS2: %llx\n", xhciDev.structParams2);
                        kprintf("  HCSPARAMS3: %llx\n", xhciDev.structParams3);
                        kprintf("  HCCPARAMS1: %llx\n", xhciDev.capParams);
                        kprintf("  DBOFF: %u\n", xhciDev.doorbellOffset);
                        kprintf("  RTSOFF: %u\n", xhciDev.rtsOffset);
                        kprintf("  HCCPARMS2: %llx\n", xhciDev.capParams2);
                        kprintf("  opRegs: %llx\n", cast(ulong)xhciDev.opRegBase);
                        
                        ushort usbStatus = xhciUsbStatus(&xhciDev);
                        kprintf("  USBSTS: %x\n", usbStatus);
                        
                        //ctrlRegs[0x00] |= 1 << 24; // OS Owned

                        //kprintf("  CAPLENGTH: %u\n", capLength);
                    }
                }
            }
        }
    }
}

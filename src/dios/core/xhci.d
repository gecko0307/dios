module dios.core.xhci;

import core.volatile;

enum XHCICapReg
{
    CAPLENGTH = 0x00,
    RSVD = 0x01,
    HCIVERSION = 0x02,
    HCSPARAMS1 = 0x04,
    HCSPARAMS2 = 0x08,
    HCSPARAMS3 = 0x0C,
    HCCPARAMS1 = 0x10,
    DBOFF = 0x14,
    RTSOFF = 0x18,
    HCCPARAMS2 = 0x1C
}

enum XHCIOpReg
{
    USBCMD = 0x00,
    USBSTS = 0x04,
    PAGESIZE = 0x08,
    DNCTRL = 0x14,
    CRCR = 0x18,
    DCBAAP = 0x30,
    CONFIG = 0x38
}

enum XHCIPort
{
    PORTSC = 0x00,
    PORTPMSC = 0x04,
    PORTLI = 0x08,
    RSVD = 0x0C
}

struct XHCIDevice
{
    void* capRegBase;
    uint capRegLength;
    uint hciVersion;
    uint structParams1;
    uint structParams2;
    uint structParams3;
    uint capParams;
    uint doorbellOffset;
    uint rtsOffset;
    uint capParams2;
    void* opRegBase;
}

extern(C):

void xhciDeviceInit(XHCIDevice* xhciDev, void* capRegs) @nogc nothrow
{
    xhciDev.capRegBase = capRegs;
    xhciDev.capRegLength = volatileLoad(cast(ubyte*)(capRegs + XHCICapReg.CAPLENGTH));
    xhciDev.hciVersion = volatileLoad(cast(ushort*)(capRegs + XHCICapReg.HCIVERSION));
    xhciDev.structParams1 = volatileLoad(cast(uint*)(capRegs + XHCICapReg.HCSPARAMS1));
    xhciDev.structParams2 = volatileLoad(cast(uint*)(capRegs + XHCICapReg.HCSPARAMS2));
    xhciDev.structParams3 = volatileLoad(cast(uint*)(capRegs + XHCICapReg.HCSPARAMS3));
    xhciDev.capParams = volatileLoad(cast(uint*)(capRegs + XHCICapReg.HCCPARAMS1));
    xhciDev.doorbellOffset = volatileLoad(cast(uint*)(capRegs + XHCICapReg.DBOFF));
    xhciDev.rtsOffset = volatileLoad(cast(uint*)(capRegs + XHCICapReg.RTSOFF));
    xhciDev.capParams2 = volatileLoad(cast(uint*)(capRegs + XHCICapReg.HCCPARAMS2));
    xhciDev.opRegBase = capRegs + xhciDev.capRegLength;
}

uint xhciUsbStatus(XHCIDevice* xhciDev) @nogc nothrow
{
    return volatileLoad(cast(uint*)(xhciDev.opRegBase + XHCIOpReg.USBSTS));
}

module core.xhci;

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
    HCCPARMS2 = 0x1C
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

// TODO
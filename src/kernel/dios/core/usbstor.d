module dios.core.usbstor;

/**
 * USB Mass Storage, Bulk-Only Transport, SCSI transparent command set.
 *
 * Every command is  CBW (31 bytes, bulk OUT)  ->  optional data  ->  CSW (13
 * bytes, bulk IN). Only what is needed to read a stick is implemented: TEST UNIT
 * READY, REQUEST SENSE, INQUIRY, READ CAPACITY(10) and READ(10). Disks over 2 TiB
 * (READ CAPACITY(16)) and writing are not supported.
 *
 * The transfers themselves (bulk TRBs, endpoint recovery) are in xhci.d; the
 * result is registered as a block device (blockdev.d).
 */
import core.volatile;

import dios.core.blockdev;
import dios.core.clock;
import dios.core.mem;
import dios.core.stdio;
import dios.core.xhci;

enum uint CBW_SIGNATURE = 0x43425355;      // "USBC"
enum uint CSW_SIGNATURE = 0x53425355;      // "USBS"

enum uint USB_MAX_DISKS = 4;

struct UsbDisk
{
    bool used;
    XhciUsbDevice* dev;
    ubyte controller;
    uint tag;
    uint sectorSize;
    ulong sectors;
    // last REQUEST SENSE
    ubyte senseKey, asc, ascq;
}

__gshared UsbDisk[USB_MAX_DISKS] usbDisks;
__gshared uint usbDiskCount;

extern(C):

void usbPut32(ubyte* p, uint v) @nogc nothrow
{
    volatileStore(p + 0, cast(ubyte)(v & 0xFF));
    volatileStore(p + 1, cast(ubyte)((v >> 8) & 0xFF));
    volatileStore(p + 2, cast(ubyte)((v >> 16) & 0xFF));
    volatileStore(p + 3, cast(ubyte)((v >> 24) & 0xFF));
}

uint usbGet32(ubyte* p) @nogc nothrow
{
    return volatileLoad(p + 0) | (cast(uint)volatileLoad(p + 1) << 8) |
           (cast(uint)volatileLoad(p + 2) << 16) | (cast(uint)volatileLoad(p + 3) << 24);
}

uint usbGetBe32(ubyte* p) @nogc nothrow
{
    return (cast(uint)volatileLoad(p + 0) << 24) | (cast(uint)volatileLoad(p + 1) << 16) |
           (cast(uint)volatileLoad(p + 2) << 8) | volatileLoad(p + 3);
}

// Bulk-Only Mass Storage Reset, then clear both endpoint halts (spec 5.3.4).
void mscResetRecovery(UsbDisk* u) @nogc nothrow
{
    XhciUsbDevice* d = u.dev;
    xhciControl(d, 0x21, 0xFF, 0, d.msc.ifaceNum, 0, 0);
    xhciClearHalt(d, true);
    xhciClearHalt(d, false);
}

/// Run one SCSI command. Returns 0 on success, 1 if the device reported a command
/// failure (CHECK CONDITION), 2 for a transport error (the device was reset).
/// Data goes through the device's bounce buffer; `got` receives the bytes moved.
int mscCommand(UsbDisk* u, const(ubyte)* cdb, uint cdbLen, bool dataIn, uint dataLen, uint* got) @nogc nothrow
{
    XhciUsbDevice* d = u.dev;
    xhciSelect(u.controller);

    ubyte* cbw = d.dma + XHCI_MSC_CBW_OFF;
    ubyte* csw = d.dma + XHCI_MSC_CSW_OFF;
    ulong cbwPhys = d.dmaPhys + XHCI_MSC_CBW_OFF;
    ulong cswPhys = d.dmaPhys + XHCI_MSC_CSW_OFF;

    for (uint i = 0; i < 32; i++)
        volatileStore(cbw + i, cast(ubyte)0);
    u.tag++;
    usbPut32(cbw, CBW_SIGNATURE);
    usbPut32(cbw + 4, u.tag);
    usbPut32(cbw + 8, dataLen);
    volatileStore(cbw + 12, cast(ubyte)(dataIn ? 0x80 : 0x00));
    volatileStore(cbw + 13, cast(ubyte)0);                      // LUN 0
    volatileStore(cbw + 14, cast(ubyte)cdbLen);
    for (uint i = 0; i < cdbLen && i < 16; i++)
        volatileStore(cbw + 15 + i, cdb[i]);

    uint actual;
    *got = 0;

    // 1. command
    if (xhciBulkXfer(d, false, cbwPhys, 31, &actual) != BULK_OK)
    {
        mscResetRecovery(u);
        return 2;
    }

    // 2. data
    if (dataLen != 0)
    {
        int rd = xhciBulkXfer(d, dataIn, d.msc.bouncePhys, dataLen, &actual);
        if (rd == BULK_STALL)
            xhciClearHalt(d, dataIn);               // the device ended the data phase early; CSW follows
        else if (rd != BULK_OK)
        {
            mscResetRecovery(u);
            return 2;
        }
        *got = actual;
    }

    // 3. status (one retry after a stall)
    int r = xhciBulkXfer(d, true, cswPhys, 13, &actual);
    if (r == BULK_STALL)
    {
        xhciClearHalt(d, true);
        r = xhciBulkXfer(d, true, cswPhys, 13, &actual);
    }
    if (r != BULK_OK || actual != 13 || usbGet32(csw) != CSW_SIGNATURE || usbGet32(csw + 4) != u.tag)
    {
        mscResetRecovery(u);
        return 2;
    }

    ubyte status = volatileLoad(csw + 12);
    if (status == 0)
        return 0;
    if (status == 1)
        return 1;
    mscResetRecovery(u);                            // phase error
    return 2;
}

void mscRequestSense(UsbDisk* u) @nogc nothrow
{
    ubyte[6] cdb;
    cdb[0] = 0x03;
    cdb[4] = 18;
    uint got;
    u.senseKey = 0;
    u.asc = 0;
    u.ascq = 0;
    if (mscCommand(u, cdb.ptr, 6, true, 18, &got) == 0 && got >= 14)
    {
        ubyte* b = u.dev.msc.bounce;
        u.senseKey = volatileLoad(b + 2) & 0x0F;
        u.asc = volatileLoad(b + 12);
        u.ascq = volatileLoad(b + 13);
    }
}

// TEST UNIT READY until the medium answers (sticks can take a second to spin up).
bool mscWaitReady(UsbDisk* u) @nogc nothrow
{
    for (uint attempt = 0; attempt < 30; attempt++)
    {
        ubyte[6] cdb;
        uint got;
        int r = mscCommand(u, cdb.ptr, 6, false, 0, &got);
        if (r == 0)
            return true;
        if (r == 1)
            mscRequestSense(u);
        clockDelayMs(100);
    }
    return false;
}

bool mscReadCapacity(UsbDisk* u) @nogc nothrow
{
    ubyte[10] cdb;
    cdb[0] = 0x25;
    uint got;
    if (mscCommand(u, cdb.ptr, 10, true, 8, &got) != 0 || got < 8)
        return false;
    ubyte* b = u.dev.msc.bounce;
    uint last = usbGetBe32(b);
    u.sectorSize = usbGetBe32(b + 4);
    u.sectors = cast(ulong)last + 1;                // 0xFFFFFFFF: capped at 2 TiB (no READ CAPACITY(16))
    return u.sectorSize == 512 || u.sectorSize == 1024 || u.sectorSize == 2048 || u.sectorSize == 4096;
}

// "VENDOR  PRODUCT         " -> "VENDOR PRODUCT"
bool mscInquiry(UsbDisk* u, char* model, uint cap) @nogc nothrow
{
    ubyte[6] cdb;
    cdb[0] = 0x12;
    cdb[4] = 36;
    uint got;
    if (mscCommand(u, cdb.ptr, 6, true, 36, &got) != 0 || got < 32)
        return false;
    ubyte* b = u.dev.msc.bounce;
    if ((volatileLoad(b) & 0x1F) != 0)              // only "direct access block device"
        return false;

    uint n = 0;
    for (uint i = 8; i < 32 && n + 1 < cap; i++)
    {
        ubyte c = volatileLoad(b + i);
        if (c < 32 || c > 126)
            c = ' ';
        if (c == ' ' && (n == 0 || model[n - 1] == ' '))
            continue;                               // squeeze blanks
        model[n++] = cast(char)c;
    }
    while (n > 0 && model[n - 1] == ' ')
        n--;
    model[n] = 0;
    return true;
}

/// READ(10) through the 64 KiB bounce buffer.
extern(C) bool usbDiskRead(void* ctx, ulong lba, uint count, void* dst) @nogc nothrow
{
    UsbDisk* u = cast(UsbDisk*)ctx;
    ubyte* out_ = cast(ubyte*)dst;

    uint maxSectors = (XHCI_MSC_BOUNCE_PAGES * 4096) / u.sectorSize;
    if (maxSectors > 65535)
        maxSectors = 65535;

    while (count != 0)
    {
        uint chunk = count < maxSectors ? count : maxSectors;
        uint bytes = chunk * u.sectorSize;

        bool ok = false;
        for (uint attempt = 0; attempt < 3 && !ok; attempt++)
        {
            ubyte[10] cdb;
            cdb[0] = 0x28;
            uint l = cast(uint)lba;
            cdb[2] = cast(ubyte)(l >> 24);
            cdb[3] = cast(ubyte)(l >> 16);
            cdb[4] = cast(ubyte)(l >> 8);
            cdb[5] = cast(ubyte)l;
            cdb[7] = cast(ubyte)(chunk >> 8);
            cdb[8] = cast(ubyte)chunk;

            uint got;
            int r = mscCommand(u, cdb.ptr, 10, true, bytes, &got);
            if (r == 0 && got == bytes)
                ok = true;
            else if (r == 1)
                mscRequestSense(u);
        }
        if (!ok)
        {
            kprintf("USB disk: read error at sector %llu (sense %x/%x/%x)\n", lba,
                    cast(uint)u.senseKey, cast(uint)u.asc, cast(uint)u.ascq);
            return false;
        }

        memcpy(out_, u.dev.msc.bounce, bytes);
        out_ += bytes;
        lba += chunk;
        count -= chunk;
    }
    return true;
}

/// Look at every storage device xhci.d brought up and register the new ones as
/// block devices (with their partitions). Safe to call again.
void usbStorageProbe() @nogc nothrow
{
    for (uint n = 0;; n++)
    {
        uint ctrl;
        XhciUsbDevice* d = xhciFindStorage(n, &ctrl);
        if (d is null)
            return;

        bool known = false;
        for (uint i = 0; i < usbDiskCount; i++)
            if (usbDisks[i].dev is d)
                known = true;
        if (known || usbDiskCount >= USB_MAX_DISKS)
            continue;

        UsbDisk* u = &usbDisks[usbDiskCount];
        *u = UsbDisk.init;
        u.dev = d;
        u.controller = cast(ubyte)ctrl;

        char[48] model;
        if (!mscWaitReady(u))
        {
            kprintf("USB storage: device is not ready (sense %x/%x/%x)\n",
                    cast(uint)u.senseKey, cast(uint)u.asc, cast(uint)u.ascq);
            continue;
        }
        if (!mscInquiry(u, model.ptr, model.length))
        {
            kprintf("USB storage: not a disk\n");
            continue;
        }
        if (!mscReadCapacity(u))
        {
            kprintf("USB storage: cannot read the capacity\n");
            continue;
        }

        char[8] name;
        name[0] = 'u'; name[1] = 's'; name[2] = 'b';
        name[3] = cast(char)('0' + usbDiskCount);
        name[4] = 0;

        u.used = true;
        usbDiskCount++;
        BlockDev* b = blockRegister(name.ptr, model.ptr, u.sectors, u.sectorSize, &usbDiskRead, u);
        if (b is null)
            continue;

        kprintf("%s: %s, %llu MiB, %u-byte sectors\n", b.name.ptr, b.model.ptr,
                (u.sectors * u.sectorSize) >> 20, u.sectorSize);
        blockScanPartitions(b);
    }
}

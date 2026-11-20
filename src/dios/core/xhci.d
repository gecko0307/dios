module dios.core.xhci;

/**
 * xHCI (USB 3.x host controller) driver + USB HID boot-protocol mouse.
 *
 * Scope: polling only (no interrupts), devices on ROOT ports only (no hubs),
 * no hot-plug. The flow is the textbook one from the xHCI spec (rev 1.2):
 *
 *   reset controller -> DCBAA + command ring + event ring -> run
 *   -> per connected port: reset port -> Enable Slot -> Address Device
 *   -> control transfers (descriptors) -> Set Configuration / Set Protocol
 *   -> Configure Endpoint -> queue Normal TRBs on the interrupt-IN endpoint
 *   -> every completed TRB is one mouse report -> mouseMove()
 *
 * All DMA memory comes from the PMM below 4 GiB, so it works whether or not
 * the controller supports 64-bit addressing. Memory shared with the
 * controller is only touched through volatileLoad/volatileStore.
 */
import core.volatile;
import dios.core.mem;
import dios.core.paging;
import dios.core.pit;
import dios.core.stdio;
import dios.core.mouse;

// constants

enum uint XHCI_MAX_SLOTS = 8;       // we only enable this many device slots
enum uint XHCI_RING_TRBS = 256;     // one 4 KiB page per ring
enum uint XHCI_RPT_BUFS = 16;       // report buffers kept queued on the mouse endpoint
enum uint XHCI_RPT_STRIDE = 64;

enum : uint
{
    // Operational register offsets
    OP_USBCMD = 0x00, OP_USBSTS = 0x04, OP_PAGESIZE = 0x08,
    OP_CRCR = 0x18, OP_DCBAAP = 0x30, OP_CONFIG = 0x38, OP_PORTS = 0x400,

    CMD_RUN = 1 << 0, CMD_HCRST = 1 << 1,
    STS_HCH = 1 << 0, STS_HSE = 1 << 2, STS_CNR = 1 << 11,

    // PORTSC bits
    PORT_CCS = 1 << 0, PORT_PED = 1 << 1, PORT_PR = 1 << 4, PORT_PP = 1 << 9,
    PORT_PRC = 1 << 21,
    // Bits that must be preserved when we write PORTSC (PP, PIC, wake enables).
    // PED and the *change* bits are write-1-to-clear: writing back what we read
    // would DISABLE the port / clear events by accident.
    PORT_PRESERVE = (1 << 9) | (3 << 14) | (7 << 25),
    PORT_CHANGE_BITS = 0x00FE0000,

    // TRB types
    TRB_NORMAL = 1, TRB_SETUP = 2, TRB_DATA = 3, TRB_STATUS = 4, TRB_LINK = 6,
    TRB_CMD_ENABLE_SLOT = 9, TRB_CMD_ADDRESS_DEVICE = 11,
    TRB_CMD_CONFIGURE_EP = 12, TRB_CMD_EVALUATE_CTX = 13, TRB_CMD_NOOP = 23,
    TRB_EV_TRANSFER = 32, TRB_EV_CMD_COMPLETE = 33, TRB_EV_PORT_STATUS = 34,

    // TRB control flags
    TRB_TC = 1 << 1,        // link: toggle cycle
    TRB_ISP = 1 << 2,       // interrupt on short packet
    TRB_IOC = 1 << 5,       // interrupt on completion (=> generate event)
    TRB_IDT = 1 << 6,       // immediate data (setup stage)
    TRB_DIR_IN = 1 << 16,

    CC_SUCCESS = 1, CC_SHORT_PACKET = 13
}

// structures

struct XhciTrb
{
    ulong param;
    uint status;
    uint control;
}

struct XhciRing
{
    XhciTrb* trbs;      // virtual
    ulong phys;
    uint enq;
    uint cycle;         // producer cycle state, 0 or 1
}

struct XhciEventRing
{
    XhciTrb* trbs;
    ulong phys;
    uint deq;
    uint cycle;         // consumer cycle state
}

// Where the fields of a mouse report live (from the HID report descriptor).
struct HidField
{
    bool valid;
    uint off;           // bit offset inside the report (after the report id byte, if any)
    uint size;          // size in bits
    bool isSigned;
}

struct HidMouseLayout
{
    bool valid;         // X and Y were found
    bool hasId;         // reports start with a report-id byte
    ubyte reportId;
    HidField x, y, wheel;
    uint btnOff;
    uint btnCount;
}

struct XhciUsbDevice
{
    bool present;
    ubyte slotId;
    ubyte port;                 // 1-based root hub port
    ubyte speed;                // PORTSC speed id: 1 FS, 2 LS, 3 HS, 4 SS
    uint ep0Mps;

    ubyte* devCtx;  ulong devCtxPhys;
    ubyte* inCtx;   ulong inCtxPhys;
    ubyte* dma;     ulong dmaPhys;   // scratch page: [0,1024) control data, [1024,..) HID report

    XhciRing ep0Ring;
    XhciRing intRing;

    // control transfer completion (set by the event handler)
    bool ep0Done;
    uint ep0Code;
    ulong ep0Wait;

    // configuration descriptor findings
    ubyte cfgValue;
    ubyte ifaceNum;
    ubyte intEpAddr;
    uint  intMps;
    ubyte intInterval;
    bool  hasMouse;

    // running mouse
    bool mouseActive;
    ubyte intDci;
    uint reportLen;
    bool gotFirstReport;
    ushort hidReportLen;        // size of the HID report descriptor (from the HID descriptor)
    HidMouseLayout layout;
    uint rptHead;               // number of reports completed so far (selects the buffer)
    uint rptsDumped;
}

struct XhciController
{
    ubyte* cap;
    ubyte* op;
    ubyte* rt;
    ubyte* db;

    uint hcs1, hcs2, hcc1;
    uint maxSlots, maxPorts;
    uint ctxSize;               // 32 or 64 bytes per context

    ulong* dcbaa;
    ulong dcbaaPhys;

    XhciRing cmdRing;
    XhciEventRing evRing;

    // command completion (set by the event handler)
    bool cmdDone;
    uint cmdCode;
    uint cmdSlot;
    ulong cmdWait;

    XhciUsbDevice[XHCI_MAX_SLOTS + 1] devs;   // indexed by slot id (0 unused)

    bool running;
}

__gshared XhciController xhci;

extern(C):

// helpers

uint xhciRd32(ubyte* base, size_t off) @nogc nothrow
{
    return volatileLoad(cast(uint*)(base + off));
}

void xhciWr32(ubyte* base, size_t off, uint v) @nogc nothrow
{
    volatileStore(cast(uint*)(base + off), v);
}

// 64-bit registers are written as two 32-bit stores, low dword first.
void xhciWr64(ubyte* base, size_t off, ulong v) @nogc nothrow
{
    xhciWr32(base, off, cast(uint)v);
    xhciWr32(base, off + 4, cast(uint)(v >> 32));
}

void xhciFence() @nogc nothrow
{
    asm @nogc nothrow { mfence; }
}

ulong xhciDeadline(uint ms) @nogc nothrow
{
    return pitTimeTicks() + (cast(ulong)ms * PIT_FREQUENCY) / 1000;
}

bool xhciWaitReg(ubyte* base, size_t off, uint mask, uint value, uint ms) @nogc nothrow
{
    ulong dl = xhciDeadline(ms);
    while ((xhciRd32(base, off) & mask) != value)
    {
        if (pitTimeTicks() > dl)
            return false;
    }
    return true;
}

// Zeroed, physically contiguous DMA memory below 4 GiB.
void* xhciDmaAlloc(ulong pages, ulong* phys) @nogc nothrow
{
    ulong p = pmmAllocContiguousZeroed(pages, 1, PMM_LIMIT_4G);
    if (p == 0)
        return null;
    *phys = p;
    return pmmPhysToVirt(p);
}

// rings

bool xhciRingInit(XhciRing* r) @nogc nothrow
{
    ulong phys;
    void* v = xhciDmaAlloc(1, &phys);
    if (v is null)
        return false;
    r.trbs = cast(XhciTrb*)v;
    r.phys = phys;
    r.enq = 0;
    r.cycle = 1;
    // Last slot is a Link TRB back to the start. Its cycle bit stays 0 (not
    // yet valid) until the producer reaches it.
    XhciTrb* link = &r.trbs[XHCI_RING_TRBS - 1];
    volatileStore(&link.param, phys);
    volatileStore(&link.status, 0u);
    volatileStore(&link.control, (TRB_LINK << 10) | TRB_TC);
    return true;
}

// Queue one TRB. Returns its physical address (that is what completion events
// refer to). The cycle bit is written last so the controller never sees a
// half-written TRB.
ulong xhciRingPush(XhciRing* r, ulong param, uint status, uint control) @nogc nothrow
{
    uint idx = r.enq;
    XhciTrb* t = &r.trbs[idx];
    volatileStore(&t.param, param);
    volatileStore(&t.status, status);
    volatileStore(&t.control, (control & ~1u) | r.cycle);
    ulong phys = r.phys + cast(ulong)idx * XhciTrb.sizeof;

    r.enq++;
    if (r.enq == XHCI_RING_TRBS - 1)
    {
        // Hand the Link TRB to the controller with the current cycle bit,
        // then wrap and flip our cycle state.
        XhciTrb* link = &r.trbs[r.enq];
        volatileStore(&link.control, (TRB_LINK << 10) | TRB_TC | r.cycle);
        r.enq = 0;
        r.cycle ^= 1;
    }
    return phys;
}

void xhciRingDoorbell(uint slot, uint target) @nogc nothrow
{
    xhciFence();
    xhciWr32(xhci.db, slot * 4, target);
}

// events

// Minimal HID report descriptor parser: finds where X, Y, wheel and the
// buttons live inside an input report. This replaces the old assumption that
// every mouse sends the 3-byte boot layout (many mice send 16-bit X/Y, so
// "byte 2" was the high byte of X: the cursor only moved sideways).
void hidParseReportDescriptor(HidMouseLayout* L, ubyte* buf, uint len) @nogc nothrow
{
    *L = HidMouseLayout.init;

    uint usagePage = 0;
    int logMin = 0;
    uint repSize = 0, repCount = 0, repId = 0;
    bool anyId = false;
    uint[16] usages;
    uint nUsages = 0, usMin = 0, usMax = 0;
    bool haveRange = false;
    uint offBits = 0;                       // within the current report id
    bool btnSeen = false;
    uint btnRid = 0, btnOff = 0, btnCount = 0;
    bool ridChosen = false;
    uint chosenRid = 0;

    uint i = 0;
    while (i < len)
    {
        ubyte b = volatileLoad(buf + i);
        if (b == 0xFE)                      // long item: skip
        {
            uint l = (i + 1 < len) ? volatileLoad(buf + i + 1) : 0;
            i += 3 + l;
            continue;
        }
        uint sz = b & 3;
        if (sz == 3) sz = 4;
        uint type = (b >> 2) & 3;
        uint tag = b >> 4;
        if (i + 1 + sz > len)
            break;

        uint val = 0;
        for (uint k = 0; k < sz; k++)
            val |= cast(uint)volatileLoad(buf + i + 1 + k) << (8 * k);
        int sval = cast(int)val;
        if (sz == 1) sval = cast(byte)val;
        else if (sz == 2) sval = cast(short)val;
        i += 1 + sz;

        if (type == 1)                      // global
        {
            if (tag == 0) usagePage = val;
            else if (tag == 1) logMin = sval;
            else if (tag == 7) repSize = val;
            else if (tag == 8) { repId = val; anyId = true; offBits = 0; }
            else if (tag == 9) repCount = val;
        }
        else if (type == 2)                 // local
        {
            if (tag == 0) { if (nUsages < 16) usages[nUsages++] = val; }
            else if (tag == 1) { usMin = val; haveRange = true; }
            else if (tag == 2) { usMax = val; haveRange = true; }
        }
        else if (type == 0)                 // main
        {
            if (tag == 8)                   // Input
            {
                bool constant = (val & 1) != 0;
                bool variable = (val & 2) != 0;

                if (!constant && variable)
                {
                    if (usagePage == 9 && !btnSeen && repSize == 1)
                    {
                        btnSeen = true;
                        btnRid = repId;
                        btnOff = offBits;
                        btnCount = repCount;
                    }

                    for (uint n = 0; n < repCount; n++)
                    {
                        uint usage = 0;
                        bool haveUsage = false;
                        if (nUsages > 0)
                        {
                            usage = usages[n < nUsages ? n : nUsages - 1];
                            haveUsage = true;
                        }
                        else if (haveRange)
                        {
                            usage = usMin + n;
                            if (usage > usMax) usage = usMax;
                            haveUsage = true;
                        }
                        if (!haveUsage || usagePage != 1)
                            continue;

                        HidField f;
                        f.valid = true;
                        f.off = offBits + n * repSize;
                        f.size = repSize;
                        f.isSigned = logMin < 0;

                        if (usage == 0x30 && !ridChosen)
                        {
                            ridChosen = true;
                            chosenRid = repId;
                        }
                        if (ridChosen && repId == chosenRid)
                        {
                            if (usage == 0x30 && !L.x.valid) L.x = f;
                            else if (usage == 0x31 && !L.y.valid) L.y = f;
                            else if (usage == 0x38 && !L.wheel.valid) L.wheel = f;
                        }
                    }
                }
                offBits += repSize * repCount;
            }
            // every main item clears the local state
            nUsages = 0;
            usMin = 0;
            usMax = 0;
            haveRange = false;
        }
    }

    if (L.x.valid && L.y.valid)
    {
        L.valid = true;
        L.hasId = anyId;
        L.reportId = cast(ubyte)chosenRid;
        if (btnSeen && btnRid == chosenRid)
        {
            L.btnOff = btnOff;
            L.btnCount = btnCount > 8 ? 8 : btnCount;
        }
    }
}

int hidGetField(ubyte* rpt, uint lenBytes, uint baseBits, HidField* f) @nogc nothrow
{
    if (!f.valid || f.size == 0 || f.size > 32)
        return 0;
    uint start = baseBits + f.off;
    if (start + f.size > lenBytes * 8)
        return 0;
    uint v = 0;
    for (uint i = 0; i < f.size; i++)
    {
        uint bit = start + i;
        uint byteV = volatileLoad(rpt + (bit >> 3));
        v |= ((byteV >> (bit & 7)) & 1) << i;
    }
    if (f.isSigned && f.size < 32 && (v & (1u << (f.size - 1))))
        v |= ~0u << f.size;
    return cast(int)v;
}

void xhciProcessReport(XhciUsbDevice* d, ubyte* rpt, uint got) @nogc nothrow
{
    // Show the first few raw reports: invaluable when a new mouse misbehaves.
    if (d.rptsDumped < 4 && got > 0)
    {
        d.rptsDumped++;
        kprintf("  report (%u bytes):", got);
        for (uint i = 0; i < got && i < 12; i++)
            kprintf(" %X", cast(uint)volatileLoad(rpt + i));
        kprintf("\n");
    }

    if (d.layout.valid)
    {
        uint base = 0;
        if (d.layout.hasId)
        {
            if (got < 1 || volatileLoad(rpt) != d.layout.reportId)
                return;
            base = 8;
        }
        int dx = hidGetField(rpt, got, base, &d.layout.x);
        int dy = hidGetField(rpt, got, base, &d.layout.y);
        int wh = hidGetField(rpt, got, base, &d.layout.wheel);
        ubyte btn = 0;
        for (uint i = 0; i < d.layout.btnCount; i++)
        {
            uint bit = base + d.layout.btnOff + i;
            if (bit < got * 8 && ((volatileLoad(rpt + (bit >> 3)) >> (bit & 7)) & 1))
                btn |= cast(ubyte)(1 << i);
        }
        mouseMove(dx, dy, btn & 0x07);
        mouse.wheel += wh;
    }
    else if (got >= 3)
    {
        // Boot protocol: buttons, dx, dy[, wheel]
        byte dx = cast(byte)volatileLoad(rpt + 1);
        byte dy = cast(byte)volatileLoad(rpt + 2);
        mouseMove(dx, dy, volatileLoad(rpt) & 0x07);
    }
}

void xhciHandleMouseEvent(XhciUsbDevice* d, uint code, uint residual) @nogc nothrow
{
    if (code != CC_SUCCESS && code != CC_SHORT_PACKET)
    {
        kprintf("USB mouse: transfer error %u, stopping\n", code);
        d.mouseActive = false;
        return;
    }

    uint buf = d.rptHead % XHCI_RPT_BUFS;
    ulong bufOff = 1024 + cast(ulong)buf * XHCI_RPT_STRIDE;
    uint len = d.reportLen;
    uint got = residual <= len ? len - residual : 0;

    if (got > 0 && !d.gotFirstReport)
    {
        d.gotFirstReport = true;
        kprintf("USB mouse: first report received\n");
    }
    xhciProcessReport(d, d.dma + bufOff, got);

    // Completions arrive in queue order, so this buffer is free again: re-queue it.
    d.rptHead++;
    xhciRingPush(&d.intRing, d.dmaPhys + bufOff, d.reportLen, (TRB_NORMAL << 10) | TRB_IOC | TRB_ISP);
    xhciRingDoorbell(d.slotId, d.intDci);
}

void xhciHandleEvent(ulong param, uint status, uint control) @nogc nothrow
{
    uint type = (control >> 10) & 0x3F;
    uint code = status >> 24;

    if (type == TRB_EV_CMD_COMPLETE)
    {
        if (param == xhci.cmdWait)
        {
            xhci.cmdCode = code;
            xhci.cmdSlot = control >> 24;
            xhci.cmdDone = true;
        }
    }
    else if (type == TRB_EV_TRANSFER)
    {
        uint slot = control >> 24;
        uint epId = (control >> 16) & 0x1F;
        if (slot == 0 || slot > XHCI_MAX_SLOTS)
            return;
        XhciUsbDevice* d = &xhci.devs[slot];
        if (epId == 1)
        {
            if (param == d.ep0Wait || (code != CC_SUCCESS && code != CC_SHORT_PACKET))
            {
                d.ep0Code = code;
                d.ep0Done = true;
            }
        }
        else if (d.mouseActive && epId == d.intDci)
        {
            xhciHandleMouseEvent(d, code, status & 0xFFFFFF);
        }
    }
    // Port status change and everything else: ignored (no hot-plug yet).
}

// Drain the event ring. Cheap when empty (one memory read), so main() can
// call it every loop iteration.
void xhciPollEvents() @nogc nothrow
{
    if (!xhci.running)
        return;

    bool any = false;
    for (;;)
    {
        XhciTrb* t = &xhci.evRing.trbs[xhci.evRing.deq];
        uint control = volatileLoad(&t.control);
        if ((control & 1) != xhci.evRing.cycle)
            break;
        ulong param = volatileLoad(&t.param);
        uint status = volatileLoad(&t.status);

        xhciHandleEvent(param, status, control);

        any = true;
        xhci.evRing.deq++;
        if (xhci.evRing.deq == XHCI_RING_TRBS)
        {
            xhci.evRing.deq = 0;
            xhci.evRing.cycle ^= 1;
        }
    }

    if (any)
    {
        // Tell the controller how far we got; bit 3 (EHB) is write-1-to-clear.
        ulong erdp = xhci.evRing.phys + cast(ulong)xhci.evRing.deq * XhciTrb.sizeof;
        xhciWr64(xhci.rt, 0x20 + 0x18, erdp | 8);
    }
}

public void usbPoll() @nogc nothrow
{
    xhciPollEvents();
}

// commands

// Run one command synchronously. Returns true if it completed with success.
bool xhciCommand(ulong param, uint control, uint* outSlot) @nogc nothrow
{
    xhci.cmdDone = false;
    xhci.cmdWait = xhciRingPush(&xhci.cmdRing, param, 0, control);
    xhciRingDoorbell(0, 0);

    ulong dl = xhciDeadline(1000);
    while (!xhci.cmdDone)
    {
        xhciPollEvents();
        if (pitTimeTicks() > dl)
        {
            kprintf("xHCI: command timed out\n");
            return false;
        }
    }
    if (xhci.cmdCode != CC_SUCCESS)
    {
        kprintf("xHCI: command failed, completion code %u\n", xhci.cmdCode);
        return false;
    }
    if (outSlot)
        *outSlot = xhci.cmdSlot;
    return true;
}

// control transfers

// EP0 control transfer. bufPhys must point to DMA memory when length != 0.
bool xhciControl(XhciUsbDevice* d, ubyte reqType, ubyte req, ushort value,
                 ushort index, ushort length, ulong bufPhys) @nogc nothrow
{
    bool dirIn = (reqType & 0x80) != 0;
    ulong setup = cast(ulong)reqType
                | (cast(ulong)req << 8)
                | (cast(ulong)value << 16)
                | (cast(ulong)index << 32)
                | (cast(ulong)length << 48);
    uint trt = length == 0 ? 0 : (dirIn ? 3 : 2);

    xhciRingPush(&d.ep0Ring, setup, 8, (TRB_SETUP << 10) | TRB_IDT | (trt << 16));
    if (length != 0)
        xhciRingPush(&d.ep0Ring, bufPhys, length, (TRB_DATA << 10) | (dirIn ? TRB_DIR_IN : 0));
    // Status stage goes the opposite way of the data stage (IN if no data).
    uint statusDir = (length != 0 && dirIn) ? 0 : TRB_DIR_IN;
    d.ep0Done = false;
    d.ep0Wait = xhciRingPush(&d.ep0Ring, 0, 0, (TRB_STATUS << 10) | TRB_IOC | statusDir);
    xhciRingDoorbell(d.slotId, 1);

    ulong dl = xhciDeadline(1000);
    while (!d.ep0Done)
    {
        xhciPollEvents();
        if (pitTimeTicks() > dl)
        {
            kprintf("USB: control transfer timed out\n");
            return false;
        }
    }
    if (d.ep0Code != CC_SUCCESS && d.ep0Code != CC_SHORT_PACKET)
    {
        kprintf("USB: control transfer failed, code %u\n", d.ep0Code);
        return false;
    }
    return true;
}

// input context

void xhciCtxW32(ubyte* ctx, uint contextIndex, uint dword, uint v) @nogc nothrow
{
    volatileStore(cast(uint*)(ctx + contextIndex * xhci.ctxSize + dword * 4), v);
}

// Fill an endpoint context. Index in the input context is dci + 1.
void xhciFillEpCtx(XhciUsbDevice* d, uint dci, uint epType, uint mps,
                   uint interval, XhciRing* ring, uint avgLen) @nogc nothrow
{
    uint ci = dci + 1;
    xhciCtxW32(d.inCtx, ci, 0, interval << 16);
    xhciCtxW32(d.inCtx, ci, 1, (3 << 1) | (epType << 3) | (mps << 16));    // CErr=3
    xhciCtxW32(d.inCtx, ci, 2, cast(uint)(ring.phys) | 1);                 // DCS=1
    xhciCtxW32(d.inCtx, ci, 3, cast(uint)(ring.phys >> 32));
    xhciCtxW32(d.inCtx, ci, 4, avgLen | (avgLen << 16));                   // avg TRB len | max ESIT
}

uint xhciDefaultEp0Mps(uint speed) @nogc nothrow
{
    if (speed == 4 || speed == 5) return 512;   // SuperSpeed
    if (speed == 3) return 64;                  // High speed
    return 8;                                   // Low/Full: learn it from the descriptor
}

// descriptors

// Walk a configuration descriptor looking for a HID boot mouse.
void xhciParseConfig(XhciUsbDevice* d, ubyte* buf, uint len) @nogc nothrow
{
    d.cfgValue = volatileLoad(buf + 5);
    bool inMouse = false;
    uint i = 0;
    while (i + 2 <= len)
    {
        uint dlen = volatileLoad(buf + i);
        uint dtype = volatileLoad(buf + i + 1);
        if (dlen < 2 || i + dlen > len)
            break;

        if (dtype == 4 && dlen >= 9)            // interface
        {
            ubyte alt = volatileLoad(buf + i + 3);
            ubyte cls = volatileLoad(buf + i + 5);
            ubyte sub = volatileLoad(buf + i + 6);
            ubyte prot = volatileLoad(buf + i + 7);
            kprintf("  iface %u alt %u: class %u sub %u proto %u\n",
                    cast(uint)volatileLoad(buf + i + 2), cast(uint)alt,
                    cast(uint)cls, cast(uint)sub, cast(uint)prot);
            inMouse = (alt == 0 && cls == 3 && sub == 1 && prot == 2 && !d.hasMouse);
            if (inMouse)
                d.ifaceNum = volatileLoad(buf + i + 2);
        }
        else if (dtype == 0x21 && dlen >= 9 && inMouse)   // HID descriptor
        {
            d.hidReportLen = cast(ushort)(volatileLoad(buf + i + 7) | (volatileLoad(buf + i + 8) << 8));
        }
        else if (dtype == 5 && dlen >= 7 && inMouse)   // endpoint
        {
            ubyte addr = volatileLoad(buf + i + 2);
            ubyte attr = volatileLoad(buf + i + 3);
            if ((addr & 0x80) && (attr & 3) == 3)       // interrupt IN
            {
                d.intEpAddr = addr;
                d.intMps = volatileLoad(buf + i + 4) | (volatileLoad(buf + i + 5) << 8);
                d.intMps &= 0x7FF;
                d.intInterval = volatileLoad(buf + i + 6);
                d.hasMouse = true;
                inMouse = false;
            }
        }
        i += dlen;
    }
}

uint xhciFloorLog2(uint v) @nogc nothrow
{
    uint r = 0;
    while (v > 1) { v >>= 1; r++; }
    return r;
}

// xHCI "Interval" is an exponent: period = 125us * 2^interval.
uint xhciEncodeInterval(uint speed, uint bInterval) @nogc nothrow
{
    if (bInterval == 0) bInterval = 1;
    if (speed == 1 || speed == 2)               // FS/LS: bInterval is in ms
    {
        uint v = xhciFloorLog2(bInterval * 8);
        if (v < 3) v = 3;
        if (v > 10) v = 10;
        return v;
    }
    uint v = bInterval - 1;                     // HS/SS: already 2^(n-1) microframes
    return v > 15 ? 15 : v;
}

// enumeration

bool xhciSetupMouse(XhciUsbDevice* d) @nogc nothrow
{
    if (!xhciControl(d, 0x00, 9, d.cfgValue, 0, 0, 0))       // Set Configuration
        return false;

    // Preferred: read the HID report descriptor and decode reports with it.
    // Fallback: force the BOOT protocol (fixed 3-byte layout).
    bool parsed = false;
    if (d.hidReportLen > 0)
    {
        uint rl = d.hidReportLen > 1000 ? 1000 : d.hidReportLen;
        if (xhciControl(d, 0x81, 6, 0x2200, d.ifaceNum, cast(ushort)rl, d.dmaPhys))
        {
            hidParseReportDescriptor(&d.layout, d.dma, rl);
            parsed = d.layout.valid;
        }
    }
    if (parsed)
    {
        kprintf("  HID layout: id %u%s, X %u@%u Y %u@%u wheel %u, %u buttons\n",
                cast(uint)d.layout.reportId, d.layout.hasId ? "".ptr : " (none)".ptr,
                d.layout.x.size, d.layout.x.off, d.layout.y.size, d.layout.y.off,
                d.layout.wheel.valid ? d.layout.wheel.size : 0u, d.layout.btnCount);
    }
    else
    {
        kprintf("  no usable report descriptor, using boot protocol\n");
        if (!xhciControl(d, 0x21, 0x0B, 0, d.ifaceNum, 0, 0))
            return false;
    }

    if (!xhciRingInit(&d.intRing))
        return false;

    uint dci = (d.intEpAddr & 0x0F) * 2 + 1;     // IN endpoint
    d.intDci = cast(ubyte)dci;
    d.reportLen = d.intMps > XHCI_RPT_STRIDE ? XHCI_RPT_STRIDE : d.intMps;

    // Configure Endpoint: add slot context (A0) and the new endpoint.
    memset(d.inCtx, 0, 4096);
    xhciCtxW32(d.inCtx, 0, 1, 1 | (1u << dci));
    xhciCtxW32(d.inCtx, 1, 0, (dci << 27) | (cast(uint)d.speed << 20));
    xhciCtxW32(d.inCtx, 1, 1, cast(uint)d.port << 16);
    xhciFillEpCtx(d, dci, 7 /* interrupt IN */, d.intMps,
                  xhciEncodeInterval(d.speed, d.intInterval), &d.intRing, d.intMps);

    if (!xhciCommand(d.inCtxPhys, (TRB_CMD_CONFIGURE_EP << 10) | (cast(uint)d.slotId << 24), null))
        return false;

    // Keep several report buffers queued: with only one, the mouse could
    // deliver at most one report per main-loop iteration.
    d.mouseActive = true;
    d.rptHead = 0;
    for (uint i = 0; i < XHCI_RPT_BUFS; i++)
        xhciRingPush(&d.intRing, d.dmaPhys + 1024 + cast(ulong)i * XHCI_RPT_STRIDE,
                     d.reportLen, (TRB_NORMAL << 10) | TRB_IOC | TRB_ISP);
    xhciRingDoorbell(d.slotId, dci);
    return true;
}

bool xhciSetupDevice(uint port, uint speed) @nogc nothrow
{
    uint slot;
    if (!xhciCommand(0, TRB_CMD_ENABLE_SLOT << 10, &slot))
        return false;
    if (slot == 0 || slot > XHCI_MAX_SLOTS)
    {
        kprintf("xHCI: unusable slot id %u\n", slot);
        return false;
    }

    XhciUsbDevice* d = &xhci.devs[slot];
    *d = XhciUsbDevice.init;
    d.slotId = cast(ubyte)slot;
    d.port = cast(ubyte)port;
    d.speed = cast(ubyte)speed;
    d.ep0Mps = xhciDefaultEp0Mps(speed);

    d.devCtx = cast(ubyte*)xhciDmaAlloc(1, &d.devCtxPhys);
    d.inCtx  = cast(ubyte*)xhciDmaAlloc(1, &d.inCtxPhys);
    d.dma    = cast(ubyte*)xhciDmaAlloc(1, &d.dmaPhys);
    if (d.devCtx is null || d.inCtx is null || d.dma is null || !xhciRingInit(&d.ep0Ring))
    {
        kprintf("xHCI: out of DMA memory\n");
        return false;
    }
    d.present = true;
    volatileStore(&xhci.dcbaa[slot], d.devCtxPhys);

    // Input context for Address Device: slot context + EP0.
    xhciCtxW32(d.inCtx, 0, 1, 0x3);                                    // add A0, A1
    xhciCtxW32(d.inCtx, 1, 0, (1u << 27) | (speed << 20));             // 1 context entry
    xhciCtxW32(d.inCtx, 1, 1, port << 16);                             // root hub port
    xhciFillEpCtx(d, 1, 4 /* control */, d.ep0Mps, 0, &d.ep0Ring, 8);

    if (!xhciCommand(d.inCtxPhys, (TRB_CMD_ADDRESS_DEVICE << 10) | (slot << 24), null))
        return false;

    // GET_DESCRIPTOR(device), first 8 bytes only -> bMaxPacketSize0.
    if (!xhciControl(d, 0x80, 6, 0x0100, 0, 8, d.dmaPhys))
        return false;
    uint mps0 = volatileLoad(d.dma + 7);
    if (speed >= 4)
        mps0 = 1u << mps0;              // SuperSpeed encodes it as 2^n
    if (mps0 != d.ep0Mps && mps0 >= 8)
    {
        d.ep0Mps = mps0;
        xhciCtxW32(d.inCtx, 0, 1, 0x2); // add A1 only
        xhciFillEpCtx(d, 1, 4, mps0, 0, &d.ep0Ring, 8);
        // The ring dequeue pointer in this context is stale; the controller
        // ignores it on Evaluate Context, only MPS is taken.
        if (!xhciCommand(d.inCtxPhys, (TRB_CMD_EVALUATE_CTX << 10) | (slot << 24), null))
            return false;
    }

    // Full device descriptor.
    if (!xhciControl(d, 0x80, 6, 0x0100, 0, 18, d.dmaPhys))
        return false;
    uint vid = volatileLoad(d.dma + 8) | (volatileLoad(d.dma + 9) << 8);
    uint pid = volatileLoad(d.dma + 10) | (volatileLoad(d.dma + 11) << 8);
    uint devClass = volatileLoad(d.dma + 4);
    kprintf("USB device on port %u: %x:%x class %u\n", port, vid, pid, devClass);
    if (devClass == 9)
    {
        kprintf("  hub - not supported yet\n");
        return true;
    }

    // Configuration descriptor: 9 bytes first to learn wTotalLength.
    if (!xhciControl(d, 0x80, 6, 0x0200, 0, 9, d.dmaPhys))
        return false;
    uint total = volatileLoad(d.dma + 2) | (volatileLoad(d.dma + 3) << 8);
    if (total > 1000) total = 1000;
    if (total < 9) total = 9;
    if (!xhciControl(d, 0x80, 6, 0x0200, 0, cast(ushort)total, d.dmaPhys))
        return false;
    xhciParseConfig(d, d.dma, total);

    if (!d.hasMouse)
    {
        kprintf("  not a HID boot mouse, ignoring\n");
        return true;
    }
    kprintf("  HID boot mouse: iface %u, ep %x, mps %u, interval %u\n",
            cast(uint)d.ifaceNum, cast(uint)d.intEpAddr, d.intMps, cast(uint)d.intInterval);

    if (!xhciSetupMouse(d))
    {
        kprintf("  mouse setup failed\n");
        return false;
    }
    kprintf("  mouse running\n");
    return true;
}

// Reset a port and return its speed id, or 0 if no enabled device results.
uint xhciResetPort(uint port) @nogc nothrow
{
    size_t off = OP_PORTS + (port - 1) * 0x10;
    uint sc = xhciRd32(xhci.op, off);

    if (!(sc & PORT_PED))
    {
        xhciWr32(xhci.op, off, (sc & PORT_PRESERVE) | PORT_PR);
        if (!xhciWaitReg(xhci.op, off, PORT_PRC, PORT_PRC, 500))
            return 0;
        pitDelayMs(10);
        sc = xhciRd32(xhci.op, off);
        xhciWr32(xhci.op, off, (sc & PORT_PRESERVE) | PORT_CHANGE_BITS); // clear change bits
        sc = xhciRd32(xhci.op, off);
    }
    else
    {
        xhciWr32(xhci.op, off, (sc & PORT_PRESERVE) | PORT_CHANGE_BITS);
    }

    if (!(sc & PORT_PED))
        return 0;
    return (sc >> 10) & 0xF;
}

void xhciEnumeratePorts() @nogc nothrow
{
    // Power every port, then give devices time to show up.
    for (uint p = 1; p <= xhci.maxPorts; p++)
    {
        size_t off = OP_PORTS + (p - 1) * 0x10;
        uint sc = xhciRd32(xhci.op, off);
        if (!(sc & PORT_PP))
            xhciWr32(xhci.op, off, (sc & PORT_PRESERVE) | PORT_PP);
    }
    pitDelayMs(150);

    // Real hardware is slower than QEMU: if nothing is connected yet, wait
    // once more before giving up.
    uint connected = 0;
    for (uint pass = 0; pass < 2 && connected == 0; pass++)
    {
        if (pass == 1)
            pitDelayMs(400);
        for (uint p = 1; p <= xhci.maxPorts; p++)
            if (xhciRd32(xhci.op, OP_PORTS + (p - 1) * 0x10) & PORT_CCS)
                connected++;
    }
    kprintf("xHCI: %u of %u ports have a device\n", connected, xhci.maxPorts);

    for (uint p = 1; p <= xhci.maxPorts; p++)
    {
        uint sc = xhciRd32(xhci.op, OP_PORTS + (p - 1) * 0x10);
        if (!(sc & PORT_CCS))
            continue;
        kprintf("xHCI: port %u: PORTSC %x\n", p, sc);
        uint speed = xhciResetPort(p);
        if (speed == 0)
        {
            kprintf("xHCI: port %u: reset failed\n", p);
            continue;
        }
        xhciSetupDevice(p, speed);
    }
}

public bool xhciMouseRunning() @nogc nothrow
{
    for (uint s = 1; s <= XHCI_MAX_SLOTS; s++)
        if (xhci.devs[s].mouseActive)
            return true;
    return false;
}

// Stop the controller (used when it has no mouse so the next one can be tried).
public void xhciShutdown() @nogc nothrow
{
    if (!xhci.running)
        return;
    xhciWr32(xhci.op, OP_USBCMD, xhciRd32(xhci.op, OP_USBCMD) & ~CMD_RUN);
    xhciWaitReg(xhci.op, OP_USBSTS, STS_HCH, STS_HCH, 500);
    xhci.running = false;
}

// controller bring-up

// Ask the BIOS to let go of the controller (USB Legacy Support capability).
void xhciLegacyHandoff() @nogc nothrow
{
    uint xecp = (xhci.hcc1 >> 16) & 0xFFFF;
    if (xecp == 0)
        return;
    ubyte* p = xhci.cap + xecp * 4;
    for (uint guard = 0; guard < 64; guard++)
    {
        uint v = xhciRd32(p, 0);
        if ((v & 0xFF) == 1)
        {
            if (v & (1u << 16)) // BIOS owns it
            {
                xhciWr32(p, 0, v | (1u << 24)); // set OS owned
                if (!xhciWaitReg(p, 0, 1u << 16, 0, 1000))
                    kprintf("xHCI: BIOS did not release the controller\n");
            }
            // Disable SMIs, clear pending SMI events.
            uint c = xhciRd32(p, 4);
            xhciWr32(p, 4, (c & 0xE1FE6) | (7u << 29));
        }
        uint next = (v >> 8) & 0xFF;
        if (next == 0)
            break;
        p += next * 4;
    }
}

// mmio: virtual address of the capability registers (BAR0).
public bool xhciInit(void* mmio) @nogc nothrow
{
    if (mmio is null)
        return false;
    xhci = XhciController.init;

    xhci.cap = cast(ubyte*)mmio;
    uint capLength = volatileLoad(xhci.cap) & 0xFF;
    uint hciVersion = volatileLoad(cast(ushort*)(xhci.cap + 2));
    xhci.hcs1 = xhciRd32(xhci.cap, 0x04);
    xhci.hcs2 = xhciRd32(xhci.cap, 0x08);
    xhci.hcc1 = xhciRd32(xhci.cap, 0x10);
    uint dboff = xhciRd32(xhci.cap, 0x14) & ~3u;
    uint rtsoff = xhciRd32(xhci.cap, 0x18) & ~0x1Fu;

    xhci.op = xhci.cap + capLength;
    xhci.rt = xhci.cap + rtsoff;
    xhci.db = xhci.cap + dboff;
    xhci.maxSlots = xhci.hcs1 & 0xFF;
    xhci.maxPorts = (xhci.hcs1 >> 24) & 0xFF;
    xhci.ctxSize = (xhci.hcc1 & (1 << 2)) ? 64 : 32;

    kprintf("xHCI: version %x, %u ports, %u slots, ctx size %u\n",
            hciVersion, xhci.maxPorts, xhci.maxSlots, xhci.ctxSize);

    xhciLegacyHandoff();

    // Stop (if running) and reset.
    uint cmd = xhciRd32(xhci.op, OP_USBCMD);
    if (cmd & CMD_RUN)
    {
        xhciWr32(xhci.op, OP_USBCMD, cmd & ~CMD_RUN);
        if (!xhciWaitReg(xhci.op, OP_USBSTS, STS_HCH, STS_HCH, 500))
            { kprintf("xHCI: would not halt\n"); return false; }
    }
    xhciWr32(xhci.op, OP_USBCMD, CMD_HCRST);
    if (!xhciWaitReg(xhci.op, OP_USBCMD, CMD_HCRST, 0, 1000) ||
        !xhciWaitReg(xhci.op, OP_USBSTS, STS_CNR, 0, 1000))
        { kprintf("xHCI: reset timed out\n"); return false; }

    if (!(xhciRd32(xhci.op, OP_PAGESIZE) & 1))
        { kprintf("xHCI: 4 KiB pages not supported\n"); return false; }

    uint slotsEn = xhci.maxSlots < XHCI_MAX_SLOTS ? xhci.maxSlots : XHCI_MAX_SLOTS;
    xhciWr32(xhci.op, OP_CONFIG, slotsEn);

    // Device Context Base Address Array (256 x 8 bytes).
    xhci.dcbaa = cast(ulong*)xhciDmaAlloc(1, &xhci.dcbaaPhys);
    if (xhci.dcbaa is null)
        return false;

    // Scratchpad buffers the controller wants for its own use.
    uint spb = (((xhci.hcs2 >> 21) & 0x1F) << 5) | ((xhci.hcs2 >> 27) & 0x1F);
    if (spb != 0)
    {
        ulong arrPhys;
        ulong* arr = cast(ulong*)xhciDmaAlloc((spb * 8 + 4095) / 4096, &arrPhys);
        if (arr is null)
            return false;
        for (uint i = 0; i < spb; i++)
        {
            ulong bp;
            if (xhciDmaAlloc(1, &bp) is null)
                return false;
            arr[i] = bp;
        }
        xhci.dcbaa[0] = arrPhys;
    }
    xhciWr64(xhci.op, OP_DCBAAP, xhci.dcbaaPhys);

    // Command ring (RCS = 1 matches our initial producer cycle state).
    if (!xhciRingInit(&xhci.cmdRing))
        return false;
    xhciWr64(xhci.op, OP_CRCR, xhci.cmdRing.phys | 1);

    // Event ring: one segment of 256 TRBs, described by a 1-entry ERST.
    ulong erstPhys;
    ulong* erst = cast(ulong*)xhciDmaAlloc(1, &erstPhys);
    void* evPage = xhciDmaAlloc(1, &xhci.evRing.phys);
    if (erst is null || evPage is null)
        return false;
    xhci.evRing.trbs = cast(XhciTrb*)evPage;
    xhci.evRing.deq = 0;
    xhci.evRing.cycle = 1;
    erst[0] = xhci.evRing.phys;
    erst[1] = XHCI_RING_TRBS;                   // size in low dword, rest reserved

    ubyte* ir = xhci.rt + 0x20;                 // interrupter 0
    xhciWr32(ir, 0x04, 0);                      // IMOD
    xhciWr32(ir, 0x08, 1);                      // ERSTSZ
    xhciWr64(ir, 0x18, xhci.evRing.phys);       // ERDP
    xhciWr64(ir, 0x10, erstPhys);               // ERSTBA - writing this enables the ring

    // Go. Interrupts stay off: we poll the event ring.
    xhciWr32(xhci.op, OP_USBCMD, CMD_RUN);
    if (!xhciWaitReg(xhci.op, OP_USBSTS, STS_HCH, 0, 500))
        { kprintf("xHCI: would not start\n"); return false; }
    xhci.running = true;

    // Smoke test of the command + event ring machinery.
    if (!xhciCommand(0, TRB_CMD_NOOP << 10, null))
        { kprintf("xHCI: No-Op command failed\n"); return false; }
    kprintf("xHCI: running\n");

    xhciEnumeratePorts();
    return true;
}

module main;

import dios.core.port;
import dios.core.vga;
import dios.core.keyboard;
import dios.core.ps2;
import dios.core.vbe;
import dios.core.framebuffer;
import dios.core.paging;
import dios.core.clock;
import dios.core.interrupts;
import dios.core.lapic;
import dios.core.cpu;
import dios.core.pci;
import dios.core.mem;
import dios.core.vmem;
import dios.core.logo;
import dios.core.cursor;
import dios.core.font;
import dios.core.console;
import dios.core.stdio;
import dios.core.error;
import dios.core.mouse;
import dios.core.gfx;
import dios.core.xhci;
import dios.bootloader.limine;

struct BootInfo
{
    const(char)* bootloaderName;
    const(char)* arguments;
    RAMInfo ramInfo;
    Framebuffer videoBuffer;
}

__gshared string EMPTY_STR = "\0";
__gshared string BOOTLOADER_LIMINE = "Limine\0";
__gshared BootInfo bootInfo;

enum size_t MAX_MEM_RANGES = 64;
__gshared MemRange[MAX_MEM_RANGES] memRanges;

extern(C):

/// Kernel entry point.
void kmain() @nogc nothrow
{
    // MUST be first: the bootloader leaves SSE disabled
    enableSSE();

    // Every Limine response can be null (request not understood)
    if (hhdmRequest.response is null ||
        memmapRequest.response is null ||
        framebufferRequest.response is null ||
        framebufferRequest.response.framebuffer_count < 1)
        hcf();

    bootInfo.bootloaderName = BOOTLOADER_LIMINE.ptr;
    bootInfo.arguments = EMPTY_STR.ptr;
    if (kernelFileRequest.response !is null && kernelFileRequest.response.kernel_file !is null &&
        kernelFileRequest.response.kernel_file.cmdline !is null)
        bootInfo.arguments = kernelFileRequest.response.kernel_file.cmdline;

    bootInfo.ramInfo.hhdmOffset = hhdmRequest.response.offset;
    if (kernelAddressRequest.response !is null)
    {
        bootInfo.ramInfo.kernelBasePhysical = cast(size_t)kernelAddressRequest.response.physical_base;
        bootInfo.ramInfo.kernelBaseVirtual = cast(size_t)kernelAddressRequest.response.virtual_base;
    }

    // Collect all usable regions
    auto memmap = memmapRequest.response;
    size_t numRanges = 0;
    ulong totalUsable = 0;
    for (ulong i = 0; i < memmap.entry_count; i++)
    {
        auto entry = memmap.entries[i];
        if (entry.type == LIMINE_MEMMAP_USABLE && numRanges < MAX_MEM_RANGES)
        {
            memRanges[numRanges].base = entry.base;
            memRanges[numRanges].length = entry.length;
            numRanges++;
            totalUsable += entry.length;
        }
        else if (entry.type == LIMINE_MEMMAP_KERNEL_AND_MODULES)
        {
            bootInfo.ramInfo.kernelSize += entry.length;
        }
    }
    bootInfo.ramInfo.availMemSize = totalUsable;

    // Physical memory manager. Must come before anything allocates
    if (!pmmInit(bootInfo.ramInfo.hhdmOffset, memRanges.ptr, numRanges))
        hcf();

    auto fb = framebufferRequest.response.framebuffers[0];
    if (fb.bpp != 32)
        hcf();

    bootInfo.videoBuffer.ptr = cast(uint*)fb.address; // already an HHDM address
    bootInfo.videoBuffer.width = cast(uint)fb.width;
    bootInfo.videoBuffer.height = cast(uint)fb.height;
    bootInfo.videoBuffer.pitch = cast(uint)fb.pitch;
    bootInfo.videoBuffer.bytesPerPixel = cast(uint)fb.bpp / 8;
    stdioMode = StdioMode.Framebuffer;

    run();
}

extern(C) void cpuFlushCache() @nogc nothrow
{
    asm @nogc nothrow
    {
        wbinvd;
    }
}

// Allocate zeroed, contiguous pages and return a usable (HHDM) pointer
void* allocBuffer(size_t bytes) @nogc nothrow
{
    ulong phys = pmmAllocContiguousZeroed(alignUp(bytes, MEM_PAGE_SIZE) / MEM_PAGE_SIZE, 1, 0);
    if (phys == 0)
        return null;
    return pmmPhysToVirt(phys);
}

__gshared Framebuffer sceneBuffer;

// Milliseconds since boot: the tick counter if the timer interrupt runs, else the clock
ulong nowMs() @nogc nothrow
{
    if (interruptStatus.tick)
        return clockTickMs();
    return clockNowNs() / 1_000_000;
}

void run() @nogc nothrow
{
    size_t hhdmOffset = bootInfo.ramInfo.hhdmOffset;
    Framebuffer* frontBuffer = &bootInfo.videoBuffer;
    size_t framebufferSize = frontBuffer.height * frontBuffer.pitch;

    // The scene: the whole picture (minus the mouse cursor) in ordinary RAM
    void* sceneAddr = allocBuffer(framebufferSize);
    if (sceneAddr is null)
        hcf();
    sceneBuffer.ptr = cast(uint*)sceneAddr;
    sceneBuffer.width = frontBuffer.width;
    sceneBuffer.height = frontBuffer.height;
    sceneBuffer.pitch = frontBuffer.pitch;
    sceneBuffer.bytesPerPixel = frontBuffer.bytesPerPixel;

    fillScreen(&sceneBuffer, 0x000000AA);
    drawBitmap(&sceneBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);

    consoleInit(&sceneBuffer, 16, 64);

    mouseInit(cast(uint)frontBuffer.width - 1, cast(uint)frontBuffer.height - 1);
    gfxInit(frontBuffer, &sceneBuffer); // from here on kprintf shows up immediately

    // From now on a CPU exception prints a register dump instead of resetting the machine
    interruptsEarlyInit();

    // MMIO mappings (LAPIC, IOAPIC, HPET) need the virtual memory manager
    if (vmemInit(&bootInfo.ramInfo) != 0)
        kPanic("vmemInit failed\n");

    // ACPI, HPET clock, LAPIC + IOAPIC, 1 kHz tick. Interrupts are enabled on return
    // (if the machine has a local APIC at all)
    interruptsInit(hhdmOffset);

    bool havePs2 = ps2Init();
    if (havePs2 && interruptStatus.ioapic)
        ps2StartIrq(interruptStatus.apicId);

    kprintf("DIOS 0.1.0\n");
    kprintf("---------------\n");
    if (!limineBaseRevisionSupported())
        kprintf("Warning: bootloader does not support base revision 3\n");
    kprintf("Bootloader: %s\n", bootInfo.bootloaderName);
    kprintf("Kernel arguments: %s\n", bootInfo.arguments);
    kprintf("HHDM offset: %llx\n", hhdmOffset);
    kprintf("Kernel base phys: %llx\n", cast(ulong)bootInfo.ramInfo.kernelBasePhysical);
    kprintf("Kernel base virt: %llx\n", cast(ulong)bootInfo.ramInfo.kernelBaseVirtual);
    kprintf("Usable memory: %llu MiB\n", cast(ulong)bootInfo.ramInfo.availMemSize / (1024 * 1024));
    kprintf("Free pages: %llu of %llu (page size %x B)\n", pmmFreeCount(), pmmTotalCount(), MEM_PAGE_SIZE);
    kprintf("Framebuffer: %ux%u %ubpp @ %llx\n",
        frontBuffer.width, frontBuffer.height, frontBuffer.bytesPerPixel * 8, cast(ulong)frontBuffer.ptr);
    kprintf("PS/2: %s\n", !havePs2 ? "absent".ptr : (ps2State.irqMode ? "present, interrupt driven".ptr : "present, polled".ptr));
    interruptsPrintStatus();

    // Enumerate PCI; this also brings up the xHCI controller(s) and any USB mouse
    pciScan();

    enum ulong BLINK_MS = 100;

    ulong nextBlink = nowMs() + BLINK_MS;

    while (1)
    {
        usbPoll();

        if (ps2State.irqMode)
            ps2Drain(); // decode what the IRQ handler queued
        else
            ps2Poll();

        // Every key press, in order (Shift state was captured when it went down)
        ubyte sc;
        bool shift;
        while (ps2PopKey(&sc, &shift))
        {
            // The console hides/restores the blinking cursor around its own drawing
            if (sc == 0x0e)
                consoleBack();
            else if (sc == 0x1C)
                consoleNewline();
            else
            {
                char c = scancodeToChar(sc, shift);
                if (c)
                    consolePrintChar(c);
            }
        }

        ulong now = nowMs();
        if (now >= nextBlink)
        {
            consoleCursorToggle();
            nextBlink = now + BLINK_MS;
        }

        // Only touches video memory if something changed (a character, the
        // blinking cursor, or the mouse moved) - and then only those pixels
        gfxPresent();

        // Sleep until the next interrupt (at most 1 ms: the timer tick). Without a
        // working tick there would be nothing to wake us, so keep spinning then
        if (interruptStatus.tick)
            cpuHlt();
    }
}

module main;

import dios.core.port;
import dios.core.vga;
import dios.core.keyboard;
import dios.core.ps2;
import dios.core.vbe;
import dios.core.framebuffer;
import dios.core.paging;
import dios.core.pit;
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
    // MUST be first: the bootloader leaves SSE disabled and the compiler uses
    // SSE even for plain struct initialisation (see REVIEW.md, section D).
    enableSSE();

    // Every Limine response can be null (request not understood). Check them
    // before dereferencing: there is no console yet, so just halt.
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

    // Collect ALL usable regions (the old code only used the largest one).
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

    // Physical memory manager. Must come before anything allocates.
    if (!pmmInit(bootInfo.ramInfo.hhdmOffset, memRanges.ptr, numRanges))
        hcf();

    auto fb = framebufferRequest.response.framebuffers[0];
    if (fb.bpp != 32)
        hcf();

    bootInfo.videoBuffer.ptr = cast(uint*)fb.address;      // already an HHDM address
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

// Allocate zeroed, contiguous pages and return a usable (HHDM) pointer.
void* allocBuffer(size_t bytes) @nogc nothrow
{
    ulong phys = pmmAllocContiguousZeroed(alignUp(bytes, MEM_PAGE_SIZE) / MEM_PAGE_SIZE, 1, 0);
    if (phys == 0)
        return null;
    return pmmPhysToVirt(phys);
}

void run() @nogc nothrow
{
    size_t hhdmOffset = bootInfo.ramInfo.hhdmOffset;
    Framebuffer* frontBuffer = &bootInfo.videoBuffer;

    size_t numPixels = frontBuffer.height * frontBuffer.width;
    size_t framebufferSize = frontBuffer.height * frontBuffer.pitch;

    void* backBufferAddr = allocBuffer(framebufferSize);
    void* consoleBufferAddr = allocBuffer(framebufferSize);
    if (backBufferAddr is null || consoleBufferAddr is null)
        hcf();

    Framebuffer backBuffer;
    backBuffer.ptr = cast(uint*)backBufferAddr;
    backBuffer.width = frontBuffer.width;
    backBuffer.height = frontBuffer.height;
    backBuffer.pitch = frontBuffer.pitch;
    backBuffer.bytesPerPixel = frontBuffer.bytesPerPixel;

    Framebuffer consoleBuffer;
    consoleBuffer.ptr = cast(uint*)consoleBufferAddr;
    consoleBuffer.width = frontBuffer.width;
    consoleBuffer.height = frontBuffer.height;
    consoleBuffer.pitch = frontBuffer.pitch;
    consoleBuffer.bytesPerPixel = frontBuffer.bytesPerPixel;

    ConsoleState* consoleState = consoleInit(&consoleBuffer, 16, 64);

    pitInit();
    mouseInit(cast(uint)frontBuffer.width - 1, cast(uint)frontBuffer.height - 1);
    bool havePs2 = ps2Init();

    uint clearColor = 0x000000AA;
    for (uint i = 0; i < numPixels; i++)
        frontBuffer.ptr[i] = clearColor;
    for (uint i = 0; i < numPixels; i++)
        backBuffer.ptr[i] = clearColor;
    for (uint i = 0; i < numPixels; i++)
        consoleBuffer.ptr[i] = clearColor;

    drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);

    kprintf("DIOS 0.0.3\n");
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
    kprintf("PS/2: %s\n", havePs2 ? "present".ptr : "absent".ptr);

    if (vmemInit(&bootInfo.ramInfo) != 0)
        kPanic("vmemInit failed\n");

    // Enumerate PCI; this also brings up the first xHCI controller and any
    // USB HID boot mouse behind one of its root ports.
    pciScan();

    // Everything below runs off the PIT tick counter. Deadlines are in ticks;
    // no per-iteration microsecond conversion (which overflowed a uint after
    // 3.6 ms and also leaked rounding error every loop).
    enum ulong INPUT_TICKS = PIT_FREQUENCY / 1000;
    enum ulong RENDER_TICKS = PIT_FREQUENCY / 60;
    enum ulong BLINK_TICKS = PIT_FREQUENCY / 10;

    ulong now = pitTimeTicks();
    ulong nextInput = now;
    ulong nextRender = now;
    ulong nextBlink = now + BLINK_TICKS;
    bool consoleCursorVisible = true;

    while (1)
    {
        now = pitTimeTicks();

        usbPoll();

        if (now >= nextInput)
        {
            ps2Poll();
            nextInput = now + INPUT_TICKS;
        }

        if (ps2State.keyPressed)
        {
            ps2State.keyPressed = 0;
            if (ps2State.lastScancode == 0x0e)
                consoleBack();
            else if (ps2State.lastScancode == 0x1C)
                consoleNewline();
            else
            {
                char c = scancodeToChar(ps2State.lastScancode);
                if (c)
                    consolePrintChar(c);
            }
        }

        if (now >= nextBlink)
        {
            consoleCursorVisible = !consoleCursorVisible;
            nextBlink = now + BLINK_TICKS;
        }

        if (now >= nextRender)
        {
            fillScreen(&backBuffer, 0x000000AA);
            drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
            consoleBlitTo(&backBuffer);
            if (consoleCursorVisible)
            {
                drawRect(&backBuffer,
                    consoleState.x + consoleState.print_x + 2,
                    consoleState.y + consoleState.print_y + consoleState.v_stride - 6,
                    0x00FFFFFF,
                    consoleState.h_stride, 3);
            }

            drawBitmap(&backBuffer, cast(uint)mouse.x, cast(uint)mouse.y, CURSOR, CURSOR_WIDTH, CURSOR_HEIGHT);

            fastMemcpyNT(frontBuffer.ptr, backBuffer.ptr, framebufferSize);
            nextRender = now + RENDER_TICKS;
        }
    }
}

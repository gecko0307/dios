module main;

import dios.core.port;
import dios.core.gdt;
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

extern(C):

__gshared size_t _end;

version(X86)
{
    import dios.bootloader.multiboot;
    
    void kmain(uint magic, uint addr) @nogc nothrow
    {
        initGDT();
        VGAConsole.init();
        
        byte status = kPortReadByte(0x64);
        if (status == 0x02)
            kPanic("Problem with GDT/CS!");
        
        if (magic != MULTIBOOT_BOOTLOADER_MAGIC)
            kPanic("Invalid Multiboot magic number");
        
        multiboot_info* mbi = cast(multiboot_info*)addr;
        
        bootInfo.bootloaderName = cast(char*)mbi.boot_loader_name;
        bootInfo.arguments = cast(char*)mbi.cmdline;
        
        bootInfo.ramInfo.availMemBase = 0;
        bootInfo.ramInfo.availMemSize = 0;
        bootInfo.ramInfo.hhdmOffset = 0;
        // TODO: MULTIBOOT_AOUT_KLUDGE
        //bootInfo.kernelBasePhysical = mbi.load_addr;
        bootInfo.ramInfo.kernelBasePhysical = 0;
        bootInfo.ramInfo.kernelBaseVirtual = 0;
        bootInfo.ramInfo.kernelSize = 0;
        
        // Memory map
        if (checkFlag(mbi.flags, 6))
        {
            multiboot_memory_map_t* mmap = cast(multiboot_memory_map_t*)(mbi.mmap_addr);
            for (mmap = cast(multiboot_memory_map_t*) mbi.mmap_addr;
                 cast(ulong)mmap < mbi.mmap_addr + mbi.mmap_length;
                 mmap = cast(multiboot_memory_map_t*)(cast(ulong)mmap + mmap.size + mmap.size.sizeof))
            {
                if ((mmap.type == 1) && (mmap.length_low > bootInfo.ramInfo.availMemSize))
                {
                    bootInfo.ramInfo.availMemBase = mmap.addr_low;
                    bootInfo.ramInfo.availMemSize = mmap.length_low;
                }
            }
        }
        
        bootInfo.ramInfo.availMemBase += 1024 * 1024; // reserve 1 MB for safety
        
        // Framebuffer
        vbeInfo* vbe;
        if ((mbi.flags & MULTIBOOT_INFO_VIDEO_INFO) != 0)
            vbe = cast(vbeInfo*)mbi.vbe_mode_info;
        else
            kPanic("No framebuffer info!");
        
        bootInfo.videoBuffer.ptr = cast(uint*)vbe.framebuffer;
        bootInfo.videoBuffer.width = vbe.width;
        bootInfo.videoBuffer.height = vbe.height;
        bootInfo.videoBuffer.pitch = vbe.pitch;
        bootInfo.videoBuffer.bytesPerPixel = vbe.bpp / 8;
        
        stdioMode = StdioMode.Framebuffer;
        
        run();
    }
}
else version(X86_64)
{
    import dios.bootloader.limine;
    
    void kmain() @nogc nothrow
    {
        // Bootloader info
        bootInfo.bootloaderName = BOOTLOADER_LIMINE.ptr;
        bootInfo.arguments = kernelFileRequest.response.kernel_file.cmdline;
        
        // Memory info
        bootInfo.ramInfo.availMemBase = 0;
        bootInfo.ramInfo.availMemSize = 0;
        bootInfo.ramInfo.hhdmOffset = hhdmRequest.response.offset;
        bootInfo.ramInfo.kernelBasePhysical = cast(size_t)kernelAddressRequest.response.physical_base;
        bootInfo.ramInfo.kernelBaseVirtual = cast(size_t)kernelAddressRequest.response.virtual_base;
        bootInfo.ramInfo.kernelSize = 0;
        
        ulong maxAddr = 0;
        
        auto memmap = memmapRequest.response;
        for (ulong i = 0; i < memmap.entry_count; i++)
        {
            auto entry = memmap.entries[i];
            
            if (entry.type == LIMINE_MEMMAP_USABLE)
            {
                if (entry.length > bootInfo.ramInfo.availMemSize)
                {
                    bootInfo.ramInfo.availMemBase = entry.base;
                    bootInfo.ramInfo.availMemSize = entry.length;
                }
            }
            else if (entry.type == LIMINE_MEMMAP_KERNEL_AND_MODULES)
            {
                bootInfo.ramInfo.kernelSize += entry.length;
            }
        }
        
        if (bootInfo.ramInfo.availMemBase == 0)
            hcf();
        
        // Framebuffer
        auto fbResp = framebufferRequest.response;
        while (fbResp is null || fbResp.framebuffer_count < 1)
        {
            asm @nogc nothrow { hlt; }
            fbResp = framebufferRequest.response;
        }
        
        auto fb = fbResp.framebuffers[0];
        
        if (fb.bpp != 32)
            hcf();
        
        bootInfo.videoBuffer.ptr = cast(uint*)fb.address;
        bootInfo.videoBuffer.width = cast(uint)fb.width;
        bootInfo.videoBuffer.height = cast(uint)fb.height;
        bootInfo.videoBuffer.pitch = cast(uint)fb.pitch;
        bootInfo.videoBuffer.bytesPerPixel = cast(uint)fb.bpp / 8;
        stdioMode = StdioMode.Framebuffer;
        
        run();
    }
}

extern(C) void cpuFlushCache() @nogc nothrow
{
    asm @nogc nothrow
    {
        wbinvd;
    }
}

enum MEM_2M_PAGE_SIZE = 0x200000UL;

void run() @nogc nothrow
{
    size_t hhdmOffset = bootInfo.ramInfo.hhdmOffset;
    size_t kernelBasePhysical = bootInfo.ramInfo.kernelBasePhysical;
    size_t kernelBaseVirtual = bootInfo.ramInfo.kernelBaseVirtual;
    size_t availMemBase = alignUp(bootInfo.ramInfo.availMemBase, MEM_2M_PAGE_SIZE);
    size_t availMemSize = bootInfo.ramInfo.availMemSize - (availMemBase - bootInfo.ramInfo.availMemBase);
    
    Framebuffer* frontBuffer = &bootInfo.videoBuffer;
    
    // Page allocator
    size_t pageAllocBase = availMemBase;
    MemPageAlloc* mem = initPages(pageAllocBase, availMemSize - (pageAllocBase - availMemBase));
    
    size_t numPixels = frontBuffer.height * frontBuffer.width;
    size_t framebufferSize = frontBuffer.height * frontBuffer.pitch;
    size_t numPagesForBuffer = alignUp(framebufferSize, MEM_PAGE_SIZE) / MEM_PAGE_SIZE;
    
    void* backBufferAddr = pagesAlloc(numPagesForBuffer, 0);
    void* consoleBufferAddr = pagesAlloc(numPagesForBuffer, 0);
    
    // Buffers for drawing kernel graphics
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
    
    // PS/2
    PS2State* ps2State = ps2Init(
        cast(uint)frontBuffer.width - 1,
        cast(uint)frontBuffer.height - 1);
    
    // Clear buffers
    uint clearColor = 0x000000AA;
    
    for (uint i = 0; i < numPixels; i++)
        frontBuffer.ptr[i] = clearColor;

    for (uint i = 0; i < numPixels; i++)
        backBuffer.ptr[i] = clearColor;
    
    for (uint i = 0; i < numPixels; i++)
        consoleBuffer.ptr[i] = clearColor;
    
    drawBitmap(&backBuffer, 16, 16, DIOS_LOGO, DIOS_LOGO_WIDTH, DIOS_LOGO_HEIGHT);
    
    // Print info
    kprintf("DIOS 0.0.2\n");
    kprintf("---------------\n");
    kprintf("Bootloader: %s\n", bootInfo.bootloaderName);
    kprintf("Kernel arguments: %s\n", bootInfo.arguments);
    version(X86)
    {
        kprintf("Avail. memory base: %x\n", availMemBase);
        kprintf("Avail. memory size: %u B (%u MiB)\n", availMemSize, availMemSize / (1024 * 1024));
        kprintf("Avail. memory end: %x\n", availMemBase + availMemSize);
        kprintf("Framebuffer: %ux%u %ubpp @ %x\n",
            frontBuffer.width, frontBuffer.height, frontBuffer.bytesPerPixel * 8, cast(size_t)frontBuffer.ptr);
    }
    else version(X86_64)
    {
        kprintf("HHDM offset: %llx\n", hhdmOffset);
        kprintf("Kernel base phys: %llx\n", kernelBasePhysical);
        kprintf("Kernel base virt: %llx\n", kernelBaseVirtual);
        kprintf("Avail. memory base: %llx\n", availMemBase);
        kprintf("Avail. memory size: %llu B (%u MiB)\n", availMemSize, availMemSize / (1024 * 1024));
        kprintf("Avail. memory end: %llx\n", availMemBase + availMemSize);
        kprintf("Framebuffer: %ux%u %ubpp @ %llx\n",
            frontBuffer.width, frontBuffer.height, frontBuffer.bytesPerPixel * 8, cast(size_t)frontBuffer.ptr);
    }
    
    kprintf("RAM page size: %x B\n", MEM_PAGE_SIZE);
    version(X86)
    {
        kprintf("RAM pages: %u\n", mem.pages.length);
        kprintf("RAM pages base: %x\n", cast(size_t)mem.ramBase);
    }
    else version(X86_64)
    {
        kprintf("RAM pages: %llu\n", mem.pages.length);
        kprintf("RAM pages base: %llx\n", cast(size_t)mem.ramBase);
    }
    
    version(X86)
    {
        // not implemented yet
    }
    else version(X86_64)
    {
        bootInfo.ramInfo.availMemBase = availMemBase;
        bootInfo.ramInfo.availMemSize = availMemSize;
        vmemInit(&bootInfo.ramInfo);
        
        // Enumerate PCI configuration space
        pciScan();
    }
    
    uint inputTimer = 0;
    uint renderTimer = 0;
    uint consoleCursorBlinkTimer = 0;
    bool consoleCursorVisible = true;
    
    uint prevTime = pitTimeTicks();
    
    while(1)
    {
        uint currTime = pitTimeTicks();
        uint delta = currTime - prevTime;
        prevTime = currTime;
        uint deltaMicroSec = (delta * 1000000) / PIT_FREQUENCY;
        
        renderTimer += deltaMicroSec;
        inputTimer += deltaMicroSec;
        consoleCursorBlinkTimer += deltaMicroSec;
        
        if (inputTimer >= 1000) // 1 millisec
        {
            ps2Poll();
            inputTimer = 0;
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
        
        if (consoleCursorBlinkTimer >= 100000)
        {
            consoleCursorVisible = !consoleCursorVisible;
            consoleCursorBlinkTimer = 0;
        }
        
        if (renderTimer >= 16666) // 16.7 millisecs
        {
            // Render
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
            
            drawBitmap(&backBuffer, ps2State.mx, ps2State.my, CURSOR, CURSOR_WIDTH, CURSOR_HEIGHT);
            
            version(X86_64)
            {
                fastMemcpyNT(frontBuffer.ptr, backBuffer.ptr, framebufferSize);
            }
            else version(X86)
            {
                for (uint i = 0; i < numPixels; i++)
                    frontBuffer.ptr[i] = backBuffer.ptr[i];
            }
           
            renderTimer = 0;
        }
    }
}

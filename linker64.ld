OUTPUT_FORMAT(elf64-x86-64)
ENTRY (kmain)

PHDRS
{
    limine_requests PT_LOAD;
    text PT_LOAD;
    rodata PT_LOAD;
    data PT_LOAD;
}

SECTIONS {
    . = 0xffffffff80000000;
    
    .limine_requests : ALIGN(0x1000) {
        KEEP(*(.limine_requests_start))
        KEEP(*(.limine_requests))
        KEEP(*(.limine_requests_end))
    } :limine_requests
    
    . = ALIGN(CONSTANT(MAXPAGESIZE));

    .text : {
        code = .; _code = .; __code = .;
        *(.text)
    }
    
    . = ALIGN(CONSTANT(MAXPAGESIZE));

    .rodata : {
        *(.rodata)
    }
    
    . = ALIGN(CONSTANT(MAXPAGESIZE));

    .data : {
        data = .; _data = .; __data = .;
        *(.data)
        start_ctors = .; *(.ctors)   end_ctors = .;
        start_dtors = .; *(.dtors)   end_dtors = .;
    }

    .bss : {
        sbss = .;
        bss = .; _bss = .; __bss = .;
        *(COMMON)
        *(.bss)
        ebss = .;
    }
    end = .; _end = .; __end = .;
}

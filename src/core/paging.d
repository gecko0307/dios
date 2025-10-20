module core.paging;

enum size_t MEM_PAGE_SIZE = 0x1000;

struct MemPage
{
    bool used;
    uint flags;
}

struct MemPageAlloc
{
    MemPage[] pages;
    void* ramBase;
    size_t ramSize;
}

__gshared MemPageAlloc memPageAlloc;

extern(C):

bool isPageAligned(size_t addr) @nogc nothrow
{
    return (addr % MEM_PAGE_SIZE) == 0;
}

MemPageAlloc* initPages(size_t basePhysAdr, size_t availableRamSize) @nogc nothrow
{
    size_t maxNumPages = availableRamSize / MEM_PAGE_SIZE;
    size_t maxPagesArraySize = maxNumPages * MemPage.sizeof;
    size_t pagesArrayNumPages = (maxPagesArraySize + MEM_PAGE_SIZE - 1) / MEM_PAGE_SIZE;
    size_t usablePages = maxNumPages - pagesArrayNumPages;
    
    void* allocPagesArrayBase = cast(void*)basePhysAdr;
    
    size_t ramStart = basePhysAdr + pagesArrayNumPages * MEM_PAGE_SIZE;
    
    memPageAlloc.ramBase = cast(void*)ramStart;
    memPageAlloc.ramSize = usablePages * MEM_PAGE_SIZE;
    
    MemPage* pagesPtr = cast(MemPage*)allocPagesArrayBase;
    memPageAlloc.pages = pagesPtr[0..usablePages];
    
    for (size_t i = 0; i < usablePages; i++)
    {
        memPageAlloc.pages[i].used = false;
        memPageAlloc.pages[i].flags = 0;
    }
    
    return &memPageAlloc;
}

void* pageAlloc(uint flags) @nogc nothrow
{
    for (size_t i = 0; i < memPageAlloc.pages.length; i++)
    {
        MemPage* page = &memPageAlloc.pages[i];
        if (!page.used)
        {
            page.used = true;
            page.flags = flags;
            return cast(void*)(cast(size_t)memPageAlloc.ramBase + i * MEM_PAGE_SIZE);
        }
    }
    return null;
}

void* pagesAlloc(size_t count, uint flags) @nogc nothrow
{
    void* first = null;
    for (size_t i = 0; i < count; i++)
    {
        void* page = pageAlloc(flags);
        if (page is null) return null;
        if (i == 0) first = page;
    }
    return first;
}

void pageFree(void* paddr) @nogc nothrow
{
    if (paddr < memPageAlloc.ramBase)
        return;

    size_t index = (cast(size_t)paddr - cast(size_t)memPageAlloc.ramBase) / MEM_PAGE_SIZE;
    if (index >= memPageAlloc.pages.length)
        return;

    memPageAlloc.pages[index].used = false;
    memPageAlloc.pages[index].flags = 0;
}

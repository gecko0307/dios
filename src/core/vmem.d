module core.vmem;

import core.paging;

enum ENTRIES_PER_TABLE = 512;

enum ulong PAGE_PRESENT   = 1UL << 0;
enum ulong PAGE_RW        = 1UL << 1;
enum ulong PAGE_USER      = 1UL << 2;
enum ulong PAGE_WRITE_THROUGH = 1UL << 3;
enum ulong PAGE_CACHE_DISABLE = 1UL << 4;
enum ulong PAGE_SIZE_FLAG = 1UL << 7;

enum ulong KERNEL_BASE = 0xffffffff80000000UL;
enum ulong KERNEL_SPACE_SIZE = 2 * 1024 * 1024;

struct PageTable
{
    ulong[ENTRIES_PER_TABLE] entries;
}

PageTable* allocPageTable()
{
    PageTable* table = cast(PageTable*)pageAlloc(0);
    for(size_t i = 0; i < ENTRIES_PER_TABLE; i++)
    {
        table.entries[i] = 0;
    }
    return table;
}

void mapPage(PageTable* pml4, ulong virt, ulong phys, ulong flags)
{
    auto pml4Index = (virt >> 39) & 0x1FF;
    auto pdptIndex = (virt >> 30) & 0x1FF;
    auto pdIndex   = (virt >> 21) & 0x1FF;
    auto ptIndex   = (virt >> 12) & 0x1FF;

    // PML4
    if ((pml4.entries[pml4Index] & PAGE_PRESENT) == 0)
        pml4.entries[pml4Index] = cast(ulong)allocPageTable() | PAGE_PRESENT | PAGE_RW;

    auto pdpt = cast(PageTable*)(pml4.entries[pml4Index] & ~0xFFFUL);

    // PDPT
    if ((pdpt.entries[pdptIndex] & PAGE_PRESENT) == 0)
        pdpt.entries[pdptIndex] = cast(ulong)allocPageTable() | PAGE_PRESENT | PAGE_RW;

    auto pd = cast(PageTable*)(pdpt.entries[pdptIndex] & ~0xFFFUL);

    // PD
    if ((pd.entries[pdIndex] & PAGE_PRESENT) == 0)
        pd.entries[pdIndex] = cast(ulong)allocPageTable() | PAGE_PRESENT | PAGE_RW;

    auto pt = cast(PageTable*)(pd.entries[pdIndex] & ~0xFFFUL);

    // PT
    pt.entries[ptIndex] = phys | flags | PAGE_PRESENT;
}

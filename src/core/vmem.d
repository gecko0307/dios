module core.vmem;

import core.mem;
import core.paging;
import stdio;

version(X86_64):

extern(C):

enum : ulong
{
    PTE_PRESENT   = 1UL << 0,
    PTE_RW        = 1UL << 1,
    PTE_USER      = 1UL << 2,
    PTE_PWT       = 1UL << 3,
    PTE_PCD       = 1UL << 4,
    PTE_ACCESSED  = 1UL << 5,
    PTE_DIRTY     = 1UL << 6,
    PTE_PSE       = 1UL << 7, // for PDE 2MiB, PDE.PS = 1
    PTE_GLOBAL    = 1UL << 8,
    // bits 9-11 are available to OS
    PTE_NX        = 1UL << 63
}

__gshared ulong HHDM_OFFSET;
__gshared ulong PML4_PHYS;

void setCR3(ulong pml4_phys) @nogc nothrow;
ulong getCR3() @nogc nothrow;

// Extract indices from virtual address
size_t idx_pml4(ulong v) @nogc nothrow { return (v >> 39) & 0x1FF; }
size_t idx_pdpt(ulong v) @nogc nothrow { return (v >> 30) & 0x1FF; }
size_t idx_pd  (ulong v) @nogc nothrow { return (v >> 21) & 0x1FF; }
size_t idx_pt  (ulong v) @nogc nothrow { return (v >> 12) & 0x1FF; }

ulong vmemPhysToVirt(ulong phys) @nogc nothrow
{
    return phys + HHDM_OFFSET;
}

int vmemInit(RAMInfo* ramInfo) @nogc nothrow
{
    if (!ramInfo) return -1;
    
    HHDM_OFFSET = ramInfo.hhdmOffset;
    
    ulong pml4_phys;
    void* pml4_virt = vmemAllocTable(&pml4_phys);
    if (!pml4_virt) return -1;
    
    // Copy the current PML4 into the new PML4 so we don't lose mappings
    // the kernel/current stack is still using. This ensures a smooth switch.
    ulong old_pml4 = getCR3();
    old_pml4 &= ~0xFFFUL;
    void* old_pml4_virt = cast(void*)vmemPhysToVirt(old_pml4);
    if (old_pml4_virt)
    {
        fastMemcpyNT(pml4_virt, old_pml4_virt, 4096);
    }
    
    PML4_PHYS = pml4_phys;
    
    kprintf("Setting up new page tables (PML4=%llx)...\n", pml4_phys);
    setCR3(pml4_phys);
    kprintf("Page tables switched successfully\n");
    
    return 0;
}

// Allocate a zeroed 4KiB page for a table, return both physical and virtual addresses.
void* vmemAllocTable(ulong* out_phys) @nogc nothrow
{
    ulong phys = cast(ulong)pageAlloc(0);
    if (phys == 0) return null;
    ulong v = vmemPhysToVirt(phys);
    memset(cast(void*)v, 0, 4096);
    if (out_phys) *out_phys = phys;
    return cast(void*)v;
}

// internal: read physical entry value at table (table_ptr is kernel virtual pointer to page table)
ulong vmemReadEntry(void* table_ptr, size_t idx) @nogc nothrow
{
    ulong *arr = cast(ulong*)table_ptr;
    return arr[idx];
}

void vmemWriteEntry(void* table_ptr, size_t idx, ulong val) @nogc nothrow
{
    ulong* arr = cast(ulong*)table_ptr;
    arr[idx] = val;
}

// Ensure that at a given level there is a table present; if not, allocate one.
// parent_table_vptr - kernel virtual ptr to parent page (PML4/PDPT/PD)
// idx - entry index
// returns kernel virtual ptr to child table and sets *out_child_phys
void* vmemEnsureChildTable(void* parent_table_vptr, size_t idx, ulong* out_child_phys) @nogc nothrow
{
    ulong ent = vmemReadEntry(parent_table_vptr, idx);
    if (ent & PTE_PRESENT)
    {
        ulong child_phys = ent & (~0xFFFUL);
        if (out_child_phys) *out_child_phys = child_phys;
        return cast(void*)vmemPhysToVirt(child_phys);
    }

    ulong child_phys = cast(ulong)pageAlloc(0);
    if (child_phys == 0) return null;
    void* child_v = cast(void*)vmemPhysToVirt(child_phys);
    if (child_v is null) return null;
    memset(child_v, 0, 4096);

    ulong newent = (child_phys & (~0xFFFUL)) | PTE_PRESENT | PTE_RW;
    vmemWriteEntry(parent_table_vptr, idx, newent);
    if (out_child_phys) *out_child_phys = child_phys;
    return child_v;
}

// Map a 4KiB page (returns 0 on success, -1 on error)
int mapPage4k(ulong pml4_phys, ulong vaddr, ulong paddr, ulong flags) @nogc nothrow
{
    void* pml4 = cast(void*)vmemPhysToVirt(pml4_phys);
    if (pml4 is null) return -1;

    size_t i4 = idx_pml4(vaddr);
    size_t i3 = idx_pdpt(vaddr);
    size_t i2 = idx_pd(vaddr);
    size_t i1 = idx_pt(vaddr);

    ulong pdpt_phys;
    void* pdpt = vmemEnsureChildTable(pml4, i4, &pdpt_phys);
    if (pdpt is null) return -1;

    ulong pd_phys;
    void* pd = vmemEnsureChildTable(pdpt, i3, &pd_phys);
    if (pd is null) return -1;

    ulong pt_phys;
    void* pt = vmemEnsureChildTable(pd, i2, &pt_phys);
    if (pt is null) return -1;

    ulong entry = (paddr & (~0xFFFUL)) | (flags & 0xFFFUL) | PTE_PRESENT;
    vmemWriteEntry(pt, i1, entry);
    return 0;
}

// Try to map using 2MiB page (PDE with PS bit). Returns 0 on success.
// If the PD entry already present and is table, it will not override; it expects empty or not present.
int mapPage2M(ulong pml4_phys, ulong vaddr, ulong paddr, ulong flags) @nogc nothrow
{
    if ((vaddr & 0x1FFFFFUL) != 0) 
    {
        kprintf("mapPage2M: vaddr %llx not aligned\n", vaddr);
        return -1; // vaddr must be 2MiB aligned
    }
    if ((paddr & 0x1FFFFFUL) != 0)
    {
        kprintf("mapPage2M: paddr %llx not aligned\n", paddr);
        return -1; // paddr must be 2MiB aligned
    }

    void* pml4 = cast(void*)vmemPhysToVirt(pml4_phys);
    if (pml4 is null)
    {
        kprintf("mapPage2M: pml4 null after vmemPhysToVirt(%llx)\n", pml4_phys);
        return -1;
    }

    size_t i4 = idx_pml4(vaddr);
    size_t i3 = idx_pdpt(vaddr);
    size_t i2 = idx_pd(vaddr);

    ulong pdpt_phys;
    void* pdpt = vmemEnsureChildTable(pml4, i4, &pdpt_phys);
    if (pdpt is null) return -1;

    ulong pd_phys;
    void* pd = vmemEnsureChildTable(pdpt, i3, &pd_phys);
    if (pd is null) return -1;

    // At PD level write a 2MiB entry with PS bit
    /*
    ulong existing = vmemReadEntry(pd, i2);
    if (existing & PTE_PRESENT)
    {
        kprintf("mapPage2M: PD entry already present at index %u\n", i2);
        return -1;
    }
    */

    ulong entry = (paddr & (~0x1FFFFFUL)) | (flags & 0xFFFUL) | PTE_PRESENT | PTE_PSE;
    //kprintf("mapPage2M: Setting PD[%u] = %llx (phys=%llx virt=%llx)\n", i2, entry, paddr, vaddr);
    vmemWriteEntry(pd, i2, entry);
    return 0;
}

// Reserve a large, unused virtual region for MMIO (example).
// Pick a canonical high-half range; adjust to your HHDM / kernel layout.
__gshared ulong MMIO_NEXT = 0xffffff1fc0000000;

// Invalidate one page in TLB
/*
void vmemInvalidatePage(void* vptr) @nogc nothrow
{
    asm { invlpg [vptr]; } // or proper D inline asm matching LDC
}
*/

// Map MMIO physical -> virtual, return virtual base (or null on error)
void* vmemMapMMIO(ulong physBase, size_t size, ulong flags = PTE_PRESENT | PTE_RW | PTE_PCD | PTE_PWT) @nogc nothrow
{
    ulong phys_end = alignUp(physBase + size, MEM_PAGE_SIZE);
    size_t mappedSize = phys_end - physBase;

    // allocate virtual range from MMIO_NEXT
    // keep it aligned to page as well
    ulong virtBase = MMIO_NEXT;
    MMIO_NEXT = virtBase + mappedSize;

    // map per 4KiB page (MMIO usually small)
    for (ulong offset = 0; offset < mappedSize; offset += MEM_PAGE_SIZE)
    {
        ulong virt = virtBase + offset;
        ulong phys = physBase + offset;
        // Use pml4 phys var you store (PML4_PHYS) - ensure mask if needed
        if (mapPage4k(PML4_PHYS, virt, phys, flags) != 0)
        {
            kprintf("Failed to map memory for MMIO!\n");
            // on failure, unmap what we already mapped (implement vmemUnmapMMIO) and return null
            return null;
        }
        // optionally invlpg for v (if replacing mapping)
        // vmemInvalidatePage(cast(void*)v); 
    }

    return cast(void*)virtBase;
}

// Unmap (simple version: clear entries) - needs vmemWriteEntry access to page tables
int vmemUnmapMMIO(void* virt, size_t size) @nogc nothrow
{
    // implement symmetric unmap: find PML4/PDPT/PD/PT and clear entries, then invlpg on pages.
    // Return 0 on success, -1 on error.

    return 0;
}

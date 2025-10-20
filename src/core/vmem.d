module core.vmem;

import core.paging;

version(X86_64):

enum ENTRIES_PER_TABLE = 512;

enum ulong PTE_ADDR_MASK = 0x000FFFFFFFFFF000UL;

enum ulong PTE_PRESENT   = 1UL << 0;
enum ulong PTE_RW        = 1UL << 1;
enum ulong PTE_USER      = 1UL << 2;
enum ulong PTE_WRITE_THROUGH = 1UL << 3;
enum ulong PTE_CACHE_DISABLE = 1UL << 4;
enum ulong PTE_ACCESSED = 1UL << 5;
enum ulong PTE_DIRTY = 1UL << 6;
enum ulong PTE_SIZE_FLAG = 1UL << 7;
enum ulong PTE_GLOBAL = 1UL << 8;
enum ulong PTE_NX = 1UL << 63;

struct PageTable
{
    ulong[ENTRIES_PER_TABLE] entries;
}

extern(C):

ulong getCR3() @nogc nothrow;

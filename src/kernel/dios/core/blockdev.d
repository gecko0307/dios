module dios.core.blockdev;

/**
 * Block devices and partition tables. A driver (usbstor.d) registers a device
 * with a read function; everything above (partitions, file systems) only ever
 * calls blockRead().
 *
 * Partition tables: GPT (when LBA 0 holds a protective MBR) and classic MBR
 * (primary partitions). A disk without a partition table - a "superfloppy" whose
 * first sector is a file system boot sector - shows up as one partition that
 * covers the whole disk.
 */
import dios.core.mem;
import dios.core.stdio;

enum uint BLK_MAX_DEVICES = 4;
enum uint BLK_MAX_PARTS = 16;

alias BlockReadFn = extern(C) bool function(void* ctx, ulong lba, uint count, void* dst) @nogc nothrow;

struct BlockDev
{
    bool present;
    char[16] name;          // "usb0"
    char[48] model;         // vendor + product, NUL terminated
    ulong sectors;
    uint sectorSize;
    BlockReadFn read;
    void* ctx;
}

struct Partition
{
    bool valid;
    ubyte dev;              // index into blockDevs
    ubyte number;           // 1-based within its disk
    bool gpt;
    ubyte mbrType;          // MBR only
    bool whole;             // no partition table: the whole disk
    ulong startLba;
    ulong sectors;
    string kind;            // human readable guess, NUL terminated literal
}

__gshared BlockDev[BLK_MAX_DEVICES] blockDevs;
__gshared uint blockDevCount;
__gshared Partition[BLK_MAX_PARTS] partitions;
__gshared uint partitionCount;
__gshared ubyte[4096] blockScratch;     // one sector, for partition table parsing

extern(C):

uint blkLe16(const(ubyte)* p) @nogc nothrow
{
    return p[0] | (cast(uint)p[1] << 8);
}

uint blkLe32(const(ubyte)* p) @nogc nothrow
{
    return p[0] | (cast(uint)p[1] << 8) | (cast(uint)p[2] << 16) | (cast(uint)p[3] << 24);
}

ulong blkLe64(const(ubyte)* p) @nogc nothrow
{
    return blkLe32(p) | (cast(ulong)blkLe32(p + 4) << 32);
}

/// Add a disk. Returns null if the table is full. `name` and `model` are copied.
BlockDev* blockRegister(const(char)* name, const(char)* model, ulong sectors, uint sectorSize,
                        BlockReadFn read, void* ctx) @nogc nothrow
{
    if (blockDevCount >= BLK_MAX_DEVICES)
        return null;
    BlockDev* b = &blockDevs[blockDevCount++];
    *b = BlockDev.init;
    uint i = 0;
    while (name[i] != 0 && i + 1 < b.name.length)
    {
        b.name[i] = name[i];
        i++;
    }
    b.name[i] = 0;
    i = 0;
    while (model[i] != 0 && i + 1 < b.model.length)
    {
        b.model[i] = model[i];
        i++;
    }
    b.model[i] = 0;
    b.present = true;
    b.sectors = sectors;
    b.sectorSize = sectorSize;
    b.read = read;
    b.ctx = ctx;
    return b;
}

/// Read `count` sectors starting at `lba`. Fails (false) outside the disk.
bool blockRead(BlockDev* b, ulong lba, uint count, void* dst) @nogc nothrow
{
    if (b is null || !b.present || count == 0)
        return false;
    if (lba >= b.sectors || b.sectors - lba < count)
        return false;
    return b.read(b.ctx, lba, count, dst);
}

uint blockDevIndex(BlockDev* b) @nogc nothrow
{
    return cast(uint)(b - blockDevs.ptr);
}

Partition* partAdd(BlockDev* b, ulong start, ulong sectors, bool gpt, ubyte mbrType, bool whole, string kind) @nogc nothrow
{
    if (partitionCount >= BLK_MAX_PARTS || sectors == 0)
        return null;
    if (start >= b.sectors || sectors > b.sectors - start)
        return null;                    // table points outside the disk: ignore it

    uint number = 1;
    for (uint i = 0; i < partitionCount; i++)
        if (partitions[i].dev == blockDevIndex(b))
            number++;

    Partition* p = &partitions[partitionCount++];
    p.valid = true;
    p.dev = cast(ubyte)blockDevIndex(b);
    p.number = cast(ubyte)number;
    p.gpt = gpt;
    p.mbrType = mbrType;
    p.whole = whole;
    p.startLba = start;
    p.sectors = sectors;
    p.kind = kind;
    return p;
}

string mbrTypeName(ubyte t) @nogc nothrow
{
    switch (t)
    {
        case 0x01: return "FAT12\0";
        case 0x04:
        case 0x06:
        case 0x0E: return "FAT16\0";
        case 0x07: return "NTFS/exFAT\0";
        case 0x0B:
        case 0x0C: return "FAT32\0";
        case 0x82: return "Linux swap\0";
        case 0x83: return "Linux\0";
        case 0xEF: return "EFI system\0";
        default: return "other\0";
    }
}

bool guidEq(const(ubyte)* a, const(ubyte)* b) @nogc nothrow
{
    for (uint i = 0; i < 16; i++)
        if (a[i] != b[i])
            return false;
    return true;
}

// On-disk (mixed endian) GUIDs
immutable ubyte[16] GUID_BASIC_DATA = [0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44, 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7];
immutable ubyte[16] GUID_EFI_SYSTEM = [0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11, 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B];

bool blockScanGpt(BlockDev* b) @nogc nothrow
{
    if (!blockRead(b, 1, 1, blockScratch.ptr))
        return false;
    const(ubyte)* h = blockScratch.ptr;
    const(char)* sig = "EFI PART";
    for (uint i = 0; i < 8; i++)
        if (h[i] != cast(ubyte)sig[i])
            return false;

    ulong entriesLba = blkLe64(h + 72);
    uint count = blkLe32(h + 80);
    uint entrySize = blkLe32(h + 84);
    if (entrySize < 128 || entrySize > b.sectorSize || count == 0 || count > 256)
        return false;

    uint perSector = b.sectorSize / entrySize;
    for (uint i = 0; i < count; i++)
    {
        if (i % perSector == 0)
            if (!blockRead(b, entriesLba + i / perSector, 1, blockScratch.ptr))
                break;
        const(ubyte)* e = blockScratch.ptr + (i % perSector) * entrySize;

        bool empty = true;
        for (uint k = 0; k < 16; k++)
            if (e[k] != 0)
                empty = false;
        if (empty)
            continue;

        ulong first = blkLe64(e + 32);
        ulong last = blkLe64(e + 40);
        if (last < first)
            continue;

        string kind = "other\0";
        if (guidEq(e, GUID_BASIC_DATA.ptr))
            kind = "basic data (FAT/exFAT/NTFS)\0";
        else if (guidEq(e, GUID_EFI_SYSTEM.ptr))
            kind = "EFI system\0";
        partAdd(b, first, last - first + 1, true, 0, false, kind);
    }
    return true;                        // a valid GPT header: never fall back to the MBR view
}

/// Find the partitions of a disk and append them to `partitions`.
void blockScanPartitions(BlockDev* b) @nogc nothrow
{
    if (b.sectorSize < 512 || b.sectorSize > 4096 || b.sectors == 0)
        return;
    if (!blockRead(b, 0, 1, blockScratch.ptr))
    {
        kprintf("%s: cannot read sector 0\n", b.name.ptr);
        return;
    }

    ubyte[512] sector0;
    memcpy(sector0.ptr, blockScratch.ptr, 512);

    // exFAT / FAT boot sector at LBA 0: no partition table, the disk is one volume.
    bool exfatVbr = sector0[3] == 'E' && sector0[4] == 'X' && sector0[5] == 'F' &&
                    sector0[6] == 'A' && sector0[7] == 'T';
    if (exfatVbr)
    {
        partAdd(b, 0, b.sectors, false, 0, true, "exFAT (whole disk)\0");
        return;
    }

    // FAT32 boot sector at LBA 0 (a stick formatted without a partition table).
    bool fatVbr = sector0[82] == 'F' && sector0[83] == 'A' && sector0[84] == 'T' &&
                  sector0[85] == '3' && sector0[86] == '2' && sector0[87] == ' ' &&
                  (sector0[0] == 0xEB || sector0[0] == 0xE9) && sector0[510] == 0x55 && sector0[511] == 0xAA;
    if (fatVbr)
    {
        partAdd(b, 0, b.sectors, false, 0, true, "FAT32 (whole disk)\0");
        return;
    }

    if (sector0[510] != 0x55 || sector0[511] != 0xAA)
        return;

    // Protective MBR -> GPT
    for (uint i = 0; i < 4; i++)
    {
        if (sector0[446 + i * 16 + 4] == 0xEE)
        {
            if (blockScanGpt(b))
                return;
            break;
        }
    }

    for (uint i = 0; i < 4; i++)
    {
        const(ubyte)* e = sector0.ptr + 446 + i * 16;
        ubyte type = e[4];
        uint start = blkLe32(e + 8);
        uint count = blkLe32(e + 12);
        if (type == 0 || count == 0 || type == 0x05 || type == 0x0F || type == 0x85 || type == 0xEE)
            continue;                   // empty or extended (logical partitions not supported)
        partAdd(b, start, count, false, type, false, mbrTypeName(type));
    }
}

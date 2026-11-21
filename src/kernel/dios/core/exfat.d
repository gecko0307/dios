module dios.core.exfat;

/**
 * exFAT, read-only.
 *
 * A volume is a boot sector (VBR), a FAT, and a cluster heap. Directories are
 * lists of 32-byte entries; a file or directory is an "entry set": one File
 * entry (0x85), one Stream Extension (0xC0: size, first cluster, flags) and one
 * or more File Name entries (0xC1, 15 UTF-16 code units each).
 *
 * A file's clusters are either a plain run (the NoFatChain flag: first, first+1,
 * ...) or a chain through the FAT. Names are shown as ASCII ('?' for anything
 * else) and matched case-insensitively for ASCII letters; the up-case table is
 * not used. Checksums of entry sets are not verified.
 */
import dios.core.blockdev;
import dios.core.mem;
import dios.core.stdio;

enum uint EXFAT_NAME_MAX = 256;
enum uint EXFAT_ATTR_DIR = 0x10;

struct ExfatVolume
{
    bool valid;
    BlockDev* dev;
    ulong partStart;            // device sector of the boot sector
    uint sectorShift;           // file system sector = 1 << sectorShift bytes
    uint clusterShift;          // cluster = 1 << clusterShift sectors
    uint devPerSector;          // file system sectors / device sectors
    ulong fatOffset;            // in file system sectors (the active FAT)
    ulong fatLength;
    ulong heapOffset;
    uint clusterCount;
    uint rootCluster;
    uint serial;
    char[16] label;
    ulong fatCacheSector;       // file system sector held in fatCache, or ~0
    ubyte[4096] fatCache;
    ulong tmpSector;            // file system sector held in tmp, or ~0
    ubyte[4096] tmp;
}

struct ExfatEntry
{
    char[EXFAT_NAME_MAX] name;
    bool isDir;
    bool noChain;
    ushort attrs;
    uint firstCluster;
    ulong size;
    ulong validSize;
    uint mtime;                 // DOS timestamp: y-1980:7 m:4 d:5 h:5 min:6 sec/2:5
}

// Where we are in a cluster chain, so sequential reads do not walk it from the start.
struct ExfatCursor
{
    bool valid;
    bool noChain;
    uint firstCluster;
    uint index;                 // cluster number within the file
    uint cluster;               // its on-disk cluster number
    ulong size;
    ulong validSize;
}

alias ExfatDirFn = extern(C) bool function(const(ExfatEntry)* e, void* ctx) @nogc nothrow;

extern(C):

uint exLe16(const(ubyte)* p) @nogc nothrow
{
    return p[0] | (cast(uint)p[1] << 8);
}

uint exLe32(const(ubyte)* p) @nogc nothrow
{
    return p[0] | (cast(uint)p[1] << 8) | (cast(uint)p[2] << 16) | (cast(uint)p[3] << 24);
}

ulong exLe64(const(ubyte)* p) @nogc nothrow
{
    return exLe32(p) | (cast(ulong)exLe32(p + 4) << 32);
}

ulong exClusterSize(ExfatVolume* v) @nogc nothrow
{
    return 1UL << (v.sectorShift + v.clusterShift);
}

// ---------------------------------------------------------------------------
// raw access
// ---------------------------------------------------------------------------

bool exReadSectors(ExfatVolume* v, ulong fsSector, uint count, void* dst) @nogc nothrow
{
    return blockRead(v.dev, v.partStart + fsSector * v.devPerSector, count * v.devPerSector, dst);
}

/// Read `len` bytes at byte offset `off` from the start of the volume.
bool exReadBytes(ExfatVolume* v, ulong off, void* dst, ulong len) @nogc nothrow
{
    ubyte* out_ = cast(ubyte*)dst;
    ulong sectorSize = 1UL << v.sectorShift;

    while (len != 0)
    {
        ulong sector = off >> v.sectorShift;
        ulong inSector = off & (sectorSize - 1);

        if (inSector == 0 && len >= sectorSize)
        {
            // Whole sectors straight into the caller's buffer (in pieces of at most 128).
            ulong n = len >> v.sectorShift;
            if (n > 128)
                n = 128;
            if (!exReadSectors(v, sector, cast(uint)n, out_))
                return false;
            ulong bytes = n << v.sectorShift;
            out_ += bytes;
            off += bytes;
            len -= bytes;
        }
        else
        {
            if (v.tmpSector != sector)
            {
                if (!exReadSectors(v, sector, 1, v.tmp.ptr))
                    return false;
                v.tmpSector = sector;       // directory scans read 32 bytes at a time: keep the sector
            }
            ulong n = sectorSize - inSector;
            if (n > len)
                n = len;
            memcpy(out_, v.tmp.ptr + inSector, cast(size_t)n);
            out_ += n;
            off += n;
            len -= n;
        }
    }
    return true;
}

ulong exClusterOffset(ExfatVolume* v, uint cluster) @nogc nothrow
{
    return (v.heapOffset + (cast(ulong)(cluster - 2) << v.clusterShift)) << v.sectorShift;
}

// Next cluster in a FAT chain; 0 at the end of the chain or on a bad entry.
uint exFatNext(ExfatVolume* v, uint cluster) @nogc nothrow
{
    ulong byteOff = (v.fatOffset << v.sectorShift) + cast(ulong)cluster * 4;
    ulong sector = byteOff >> v.sectorShift;
    if (v.fatCacheSector != sector)
    {
        if (!exReadSectors(v, sector, 1, v.fatCache.ptr))
            return 0;
        v.fatCacheSector = sector;
    }
    uint next = exLe32(v.fatCache.ptr + (byteOff & ((1UL << v.sectorShift) - 1)));
    if (next < 2 || next >= v.clusterCount + 2)
        return 0;
    return next;
}

// Cluster number of the index-th cluster of the stream, or 0 if it does not exist.
uint exSeek(ExfatVolume* v, ExfatCursor* c, uint index) @nogc nothrow
{
    if (!c.valid || index < c.index)
    {
        c.valid = true;
        c.index = 0;
        c.cluster = c.firstCluster;
    }
    while (c.index < index)
    {
        if (c.noChain)
            c.cluster++;
        else
        {
            c.cluster = exFatNext(v, c.cluster);
            if (c.cluster == 0)
                return 0;
        }
        c.index++;
    }
    if (c.cluster < 2 || c.cluster >= v.clusterCount + 2)
        return 0;
    return c.cluster;
}

/// Read up to `len` bytes of a stream at `offset`. Returns how many were read
/// (short at the end of the stream or on an I/O error).
ulong exStreamRead(ExfatVolume* v, ExfatCursor* c, ulong offset, void* dst, ulong len) @nogc nothrow
{
    if (offset >= c.size)
        return 0;
    if (len > c.size - offset)
        len = c.size - offset;

    ubyte* out_ = cast(ubyte*)dst;
    ulong clusterSize = exClusterSize(v);
    ulong total = 0;

    while (len != 0)
    {
        ulong index = offset / clusterSize;
        ulong inCluster = offset % clusterSize;
        uint cl = exSeek(v, c, cast(uint)index);
        if (cl == 0)
            break;

        ulong n = clusterSize - inCluster;
        if (n > len)
            n = len;
        if (!exReadBytes(v, exClusterOffset(v, cl) + inCluster, out_, n))
            break;

        out_ += n;
        offset += n;
        len -= n;
        total += n;
    }

    // Bytes past ValidDataLength read as zero.
    if (c.validSize < c.size)
    {
        ulong start = offset - total;           // offset of the first byte we returned
        ubyte* base = cast(ubyte*)dst;
        for (ulong i = 0; i < total; i++)
            if (start + i >= c.validSize)
                base[i] = 0;
    }
    return total;
}

// Length of a cluster chain in bytes (used for the root directory, which has no size field).
ulong exChainBytes(ExfatVolume* v, uint first) @nogc nothrow
{
    ulong n = 0;
    uint cl = first;
    while (cl != 0 && n < v.clusterCount)
    {
        n++;
        cl = exFatNext(v, cl);
    }
    return n * exClusterSize(v);
}

// ---------------------------------------------------------------------------
// mounting
// ---------------------------------------------------------------------------

void exRootEntry(ExfatVolume* v, ExfatEntry* e) @nogc nothrow
{
    *e = ExfatEntry.init;
    e.name[0] = 0;
    e.isDir = true;
    e.attrs = EXFAT_ATTR_DIR;
    e.noChain = false;
    e.firstCluster = v.rootCluster;
    e.size = exChainBytes(v, v.rootCluster);
    e.validSize = e.size;
}

void exCursorFor(ExfatCursor* c, const(ExfatEntry)* e) @nogc nothrow
{
    c.valid = false;
    c.noChain = e.noChain;
    c.firstCluster = e.firstCluster;
    c.index = 0;
    c.cluster = e.firstCluster;
    c.size = e.size;
    c.validSize = e.validSize;
}

// Volume label: a 0x83 entry in the root directory.
void exReadLabel(ExfatVolume* v) @nogc nothrow
{
    v.label[0] = 0;

    ExfatEntry root;
    exRootEntry(v, &root);
    ExfatCursor cur;
    exCursorFor(&cur, &root);

    ubyte[32] ent;
    for (ulong pos = 0; pos + 32 <= root.size; pos += 32)
    {
        if (exStreamRead(v, &cur, pos, ent.ptr, 32) != 32)
            return;
        if (ent[0] == 0)
            return;
        if (ent[0] == 0x83)
        {
            uint n = ent[1];
            if (n > 11)
                n = 11;
            for (uint i = 0; i < n; i++)
            {
                uint ch = exLe16(ent.ptr + 2 + i * 2);
                v.label[i] = (ch >= 32 && ch < 127) ? cast(char)ch : '?';
            }
            v.label[n] = 0;
            return;
        }
    }
}

/// Try to mount the volume that starts at device sector `startLba`.
bool exfatMount(ExfatVolume* v, BlockDev* dev, ulong startLba, ulong sectors) @nogc nothrow
{
    *v = ExfatVolume.init;
    v.dev = dev;
    v.partStart = startLba;
    v.fatCacheSector = ~0UL;
    v.tmpSector = ~0UL;

    if (dev.sectorSize > 4096 || !blockRead(dev, startLba, 1, v.tmp.ptr))
        return false;
    const(ubyte)* b = v.tmp.ptr;

    const(char)* sig = "EXFAT   ";
    for (uint i = 0; i < 8; i++)
        if (b[3 + i] != cast(ubyte)sig[i])
            return false;
    for (uint i = 11; i < 64; i++)
        if (b[i] != 0)
            return false;               // MustBeZero
    if (b[510] != 0x55 || b[511] != 0xAA)
        return false;

    uint sectorShift = b[108];
    uint clusterShift = b[109];
    if (sectorShift < 9 || sectorShift > 12 || clusterShift > 25 - sectorShift)
    {
        kprintf("exFAT: unsupported geometry\n");
        return false;
    }
    if ((1u << sectorShift) < dev.sectorSize)
    {
        kprintf("exFAT: %u-byte file system sectors on a disk with %u-byte sectors\n",
                1u << sectorShift, dev.sectorSize);
        return false;
    }

    ulong volumeLength = exLe64(b + 72);
    ulong fatOffset = exLe32(b + 80);
    ulong fatLength = exLe32(b + 84);
    ulong heapOffset = exLe32(b + 88);
    uint clusterCount = exLe32(b + 92);
    uint rootCluster = exLe32(b + 96);
    uint flags = exLe16(b + 106);
    uint numFats = b[110];

    if (clusterCount == 0 || rootCluster < 2 || rootCluster >= clusterCount + 2 ||
        heapOffset + (cast(ulong)clusterCount << clusterShift) > volumeLength ||
        (numFats != 1 && numFats != 2) || fatOffset == 0)
    {
        kprintf("exFAT: damaged boot sector\n");
        return false;
    }
    if (numFats == 2 && (flags & 1))
        fatOffset += fatLength;         // the second FAT is the active one

    v.sectorShift = sectorShift;
    v.clusterShift = clusterShift;
    v.devPerSector = (1u << sectorShift) / dev.sectorSize;
    v.fatOffset = fatOffset;
    v.fatLength = fatLength;
    v.heapOffset = heapOffset;
    v.clusterCount = clusterCount;
    v.rootCluster = rootCluster;
    v.serial = exLe32(b + 100);
    v.valid = true;

    exReadLabel(v);
    return true;
}

// ---------------------------------------------------------------------------
// directories
// ---------------------------------------------------------------------------

/// Call `fn` for every file and directory in `dir`, in on-disk order. `fn`
/// returns false to stop. Returns false only on an I/O or structure error.
bool exfatIterate(ExfatVolume* v, const(ExfatEntry)* dir, ExfatDirFn fn, void* ctx) @nogc nothrow
{
    if (!dir.isDir)
        return false;

    ExfatCursor cur;
    exCursorFor(&cur, dir);
    cur.validSize = cur.size;

    ubyte[32] ent;
    ExfatEntry e;

    ulong pos = 0;
    while (pos + 32 <= dir.size)
    {
        if (exStreamRead(v, &cur, pos, ent.ptr, 32) != 32)
            return false;

        ubyte type = ent[0];
        if (type == 0)
            return true;                // end of directory
        if (type != 0x85)
        {
            pos += 32;                  // volume label, bitmap, up-case table, deleted entries...
            continue;
        }

        uint secondary = ent[1];
        if (secondary < 2 || secondary > 18)
        {
            pos += 32;
            continue;
        }

        e = ExfatEntry.init;
        e.attrs = cast(ushort)exLe16(ent.ptr + 4);
        e.isDir = (e.attrs & EXFAT_ATTR_DIR) != 0;
        e.mtime = exLe32(ent.ptr + 12);

        bool ok = true;
        uint nameLen = 0;
        uint got = 0;
        for (uint i = 1; i <= secondary && ok; i++)
        {
            if (exStreamRead(v, &cur, pos + i * 32, ent.ptr, 32) != 32)
                return false;

            if (i == 1)
            {
                if (ent[0] != 0xC0)
                {
                    ok = false;
                    break;
                }
                e.noChain = (ent[1] & 2) != 0;
                nameLen = ent[3];
                e.validSize = exLe64(ent.ptr + 8);
                e.firstCluster = exLe32(ent.ptr + 20);
                e.size = exLe64(ent.ptr + 24);
                if (nameLen == 0 || nameLen > 255)
                    ok = false;
            }
            else if (ent[0] == 0xC1)
            {
                for (uint k = 0; k < 15 && got < nameLen; k++)
                {
                    uint ch = exLe16(ent.ptr + 2 + k * 2);
                    e.name[got++] = (ch >= 32 && ch < 127) ? cast(char)ch : '?';
                }
            }
        }

        pos += 32 + cast(ulong)secondary * 32;
        if (!ok || got != nameLen)
            continue;
        e.name[got] = 0;
        if (e.validSize > e.size)
            e.validSize = e.size;

        if (!fn(&e, ctx))
            return true;
    }
    return true;
}

char exLower(char c) @nogc nothrow
{
    return (c >= 'A' && c <= 'Z') ? cast(char)(c + 32) : c;
}

struct ExfatFindCtx
{
    const(char)* name;
    uint len;
    ExfatEntry* result;
    bool found;
}

extern(C) bool exFindCb(const(ExfatEntry)* e, void* ctx) @nogc nothrow
{
    ExfatFindCtx* f = cast(ExfatFindCtx*)ctx;
    uint i = 0;
    while (i < f.len && e.name[i] != 0 && exLower(e.name[i]) == exLower(f.name[i]))
        i++;
    if (i == f.len && e.name[i] == 0)
    {
        *f.result = *e;
        f.found = true;
        return false;
    }
    return true;
}

/// Look up `path` ("/dir/file", components separated by '/'; no "." or "..").
/// "/" gives the root directory.
bool exfatLookup(ExfatVolume* v, const(char)* path, ExfatEntry* result) @nogc nothrow
{
    exRootEntry(v, result);

    const(char)* p = path;
    for (;;)
    {
        while (*p == '/')
            p++;
        if (*p == 0)
            return true;

        const(char)* start = p;
        while (*p != 0 && *p != '/')
            p++;
        uint len = cast(uint)(p - start);
        if (len > 255)
            return false;

        ExfatFindCtx ctx;
        ctx.name = start;
        ctx.len = len;
        ctx.result = result;
        ctx.found = false;

        ExfatEntry dir = *result;
        if (!dir.isDir || !exfatIterate(v, &dir, &exFindCb, &ctx) || !ctx.found)
            return false;
    }
}

// ---------------------------------------------------------------------------
// files
// ---------------------------------------------------------------------------

struct ExfatFile
{
    ExfatCursor cur;
    ulong size;
}

bool exfatOpen(ExfatFile* f, const(ExfatEntry)* e) @nogc nothrow
{
    if (e.isDir)
        return false;
    exCursorFor(&f.cur, e);
    f.size = e.size;
    return true;
}

/// Read from an open file. Returns the number of bytes read (0 at the end).
ulong exfatRead(ExfatVolume* v, ExfatFile* f, ulong offset, void* dst, ulong len) @nogc nothrow
{
    return exStreamRead(v, &f.cur, offset, dst, len);
}

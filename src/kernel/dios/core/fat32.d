module dios.core.fat32;

/**
 * Read-only FAT32. It plugs into the exFAT code (exfat.d): a FAT32 volume fills
 * the same ExfatVolume fields (FAT position, cluster geometry, root cluster), so
 * cluster chains, file reads and path lookup are shared. Only mounting and
 * directory parsing (8.3 entries plus long file names) differ.
 *
 * FAT12/FAT16 are not supported (their root directory is a fixed area, not a
 * cluster chain).
 */
import dios.core.blockdev;
import dios.core.exfat;
import dios.core.stdio;

enum ubyte FAT_ATTR_VOLUME = 0x08;
enum ubyte FAT_ATTR_DIR = 0x10;
enum ubyte FAT_ATTR_LFN = 0x0F;

extern(C):

uint fatShiftOf(uint x) @nogc nothrow
{
    if (x == 0 || (x & (x - 1)) != 0)
        return 0xFF;
    uint s = 0;
    while ((1u << s) != x)
        s++;
    return s;
}

/// Try to mount a FAT32 volume starting at device sector `startLba`.
/// Quiet when the sector is not a FAT32 boot sector.
bool fat32Mount(ExfatVolume* v, BlockDev* dev, ulong startLba, ulong sectors) @nogc nothrow
{
    *v = ExfatVolume.init;
    v.dev = dev;
    v.partStart = startLba;
    v.fatCacheSector = ~0UL;
    v.tmpSector = ~0UL;

    if (dev.sectorSize > 4096 || !blockRead(dev, startLba, 1, v.tmp.ptr))
        return false;
    const(ubyte)* b = v.tmp.ptr;
    if (b[510] != 0x55 || b[511] != 0xAA)
        return false;

    uint bytesPerSector = exLe16(b + 11);
    uint perCluster = b[13];
    uint reserved = exLe16(b + 14);
    uint numFats = b[16];
    uint rootEntries = exLe16(b + 17);
    uint fatSize16 = exLe16(b + 22);
    uint fatSize32 = exLe32(b + 36);
    ulong total = exLe16(b + 19);
    if (total == 0)
        total = exLe32(b + 32);

    uint sectorShift = fatShiftOf(bytesPerSector);
    uint clusterShift = fatShiftOf(perCluster);
    if (sectorShift < 9 || sectorShift > 12 || clusterShift == 0xFF)
        return false;                   // also rejects exFAT (bytes per sector field is zero)
    if (rootEntries != 0 || fatSize16 != 0 || fatSize32 == 0 || total == 0 || reserved == 0 ||
        numFats < 1 || numFats > 4)
        return false;                   // FAT12/FAT16 or not a FAT at all

    if (clusterShift > 25 - sectorShift)
    {
        kprintf("FAT32: unsupported geometry\n");
        return false;
    }
    if ((1u << sectorShift) < dev.sectorSize)
    {
        kprintf("FAT32: %u-byte file system sectors on a disk with %u-byte sectors\n",
                1u << sectorShift, dev.sectorSize);
        return false;
    }

    ulong dataStart = reserved + cast(ulong)numFats * fatSize32;
    if (total <= dataStart)
    {
        kprintf("FAT32: damaged boot sector\n");
        return false;
    }
    ulong clusters = (total - dataStart) >> clusterShift;
    uint rootCluster = exLe32(b + 44);
    if (clusters == 0 || clusters > 0x0FFFFFF5 ||
        ((cast(ulong)fatSize32 << sectorShift) / 4) < clusters + 2 ||
        rootCluster < 2 || rootCluster >= clusters + 2)
    {
        kprintf("FAT32: damaged boot sector\n");
        return false;
    }

    // With mirroring off, bits 0-3 of the flags name the one active FAT.
    uint flags = exLe16(b + 40);
    uint active = (flags & 0x80) ? (flags & 0xF) : 0;
    if (active >= numFats)
        active = 0;

    v.sectorShift = sectorShift;
    v.clusterShift = clusterShift;
    v.devPerSector = (1u << sectorShift) / dev.sectorSize;
    v.fatOffset = reserved + cast(ulong)active * fatSize32;
    v.fatLength = fatSize32;
    v.heapOffset = dataStart;
    v.clusterCount = cast(uint)clusters;
    v.rootCluster = rootCluster;
    v.serial = exLe32(b + 67);
    v.fat32 = true;
    v.fat32Iter = &fat32Iterate;

    v.label[0] = 0;
    if (b[66] == 0x29)
    {
        uint n = 0;
        for (uint i = 0; i < 11; i++)
        {
            ubyte c = b[71 + i];
            v.label[i] = (c >= 32 && c < 127) ? cast(char)c : '?';
            if (c != ' ')
                n = i + 1;
        }
        v.label[n] = 0;
        if (n == 7 && v.label[0] == 'N' && v.label[1] == 'O' && v.label[3] == 'N')
            v.label[0] = 0;             // "NO NAME"
    }
    v.valid = true;
    return true;
}

ubyte fat32Checksum(const(ubyte)* name11) @nogc nothrow
{
    ubyte sum = 0;
    for (uint i = 0; i < 11; i++)
        sum = cast(ubyte)(((sum & 1) << 7) + (sum >> 1) + name11[i]);
    return sum;
}

char fat32Ascii(uint ch) @nogc nothrow
{
    return (ch >= 32 && ch < 127) ? cast(char)ch : '?';
}

/// Directory walk, same contract as exfatIterate().
bool fat32Iterate(ExfatVolume* v, const(ExfatEntry)* dir, ExfatDirFn fn, void* ctx) @nogc nothrow
{
    if (!dir.isDir)
        return false;
    if (dir.firstCluster < 2)
        return true;

    ulong dirBytes = exChainBytes(v, dir.firstCluster);     // directories carry no size on disk
    ExfatCursor cur;
    cur.valid = false;
    cur.noChain = false;
    cur.firstCluster = dir.firstCluster;
    cur.index = 0;
    cur.cluster = dir.firstCluster;
    cur.size = dirBytes;
    cur.validSize = dirBytes;

    ubyte[32] ent;
    ExfatEntry e;
    char[272] lfn;                      // long name collected so far (ASCII, NUL padded)
    bool lfnActive = false;
    uint lfnNext = 0;                   // sequence number of the next long name entry we expect
    ubyte lfnSum = 0;

    for (ulong pos = 0; pos + 32 <= dirBytes; pos += 32)
    {
        if (exStreamRead(v, &cur, pos, ent.ptr, 32) != 32)
            return false;

        ubyte first = ent[0];
        if (first == 0)
            return true;                // end of directory
        if (first == 0xE5)
        {
            lfnActive = false;
            continue;
        }

        ubyte attr = ent[11];
        if ((attr & 0x3F) == FAT_ATTR_LFN)
        {
            uint seq = first & 0x3F;
            if (first & 0x40)
            {
                if (seq == 0 || seq > 20)
                {
                    lfnActive = false;
                    continue;
                }
                for (uint i = 0; i < lfn.length; i++)
                    lfn[i] = 0;
                lfnActive = true;
                lfnSum = ent[13];
            }
            else if (!lfnActive || seq != lfnNext || ent[13] != lfnSum)
            {
                lfnActive = false;
                continue;
            }
            lfnNext = seq - 1;

            uint at = (seq - 1) * 13;
            uint k = 0;
            for (uint i = 0; i < 13; i++)
            {
                uint off = i < 5 ? 1 + i * 2 : (i < 11 ? 14 + (i - 5) * 2 : 28 + (i - 11) * 2);
                uint ch = exLe16(ent.ptr + off);
                if (ch == 0 || ch == 0xFFFF)
                    break;
                lfn[at + k] = fat32Ascii(ch);
                k++;
            }
            continue;
        }

        bool haveLfn = lfnActive && lfnNext == 0 && lfnSum == fat32Checksum(ent.ptr);
        lfnActive = false;

        if (attr & FAT_ATTR_VOLUME)
            continue;                   // volume label
        if (first == '.' && (ent[1] == ' ' || (ent[1] == '.' && ent[2] == ' ')))
            continue;                   // "." and ".."

        e = ExfatEntry.init;
        uint n = 0;
        if (haveLfn)
        {
            while (n < 255 && lfn[n] != 0)
            {
                e.name[n] = lfn[n];
                n++;
            }
        }
        if (n == 0)
        {
            bool lowBase = (ent[12] & 0x08) != 0;
            bool lowExt = (ent[12] & 0x10) != 0;
            uint baseLen = 8;
            while (baseLen > 0 && ent[baseLen - 1] == ' ')
                baseLen--;
            uint extLen = 3;
            while (extLen > 0 && ent[8 + extLen - 1] == ' ')
                extLen--;
            for (uint i = 0; i < baseLen; i++)
            {
                uint c = (i == 0 && first == 0x05) ? 0xE5 : ent[i];
                char ch = fat32Ascii(c);
                e.name[n++] = (lowBase && ch >= 'A' && ch <= 'Z') ? cast(char)(ch + 32) : ch;
            }
            if (extLen != 0)
            {
                e.name[n++] = '.';
                for (uint i = 0; i < extLen; i++)
                {
                    char ch = fat32Ascii(ent[8 + i]);
                    e.name[n++] = (lowExt && ch >= 'A' && ch <= 'Z') ? cast(char)(ch + 32) : ch;
                }
            }
        }
        e.name[n] = 0;
        if (n == 0)
            continue;

        e.attrs = attr;
        e.isDir = (attr & FAT_ATTR_DIR) != 0;
        e.noChain = false;
        e.firstCluster = (exLe16(ent.ptr + 20) << 16) | exLe16(ent.ptr + 26);
        e.mtime = (exLe16(ent.ptr + 24) << 16) | exLe16(ent.ptr + 22);
        if (e.isDir)
            e.size = 0;
        else
            e.size = (e.firstCluster < 2) ? 0 : exLe32(ent.ptr + 28);
        e.validSize = e.size;

        if (!fn(&e, ctx))
            return true;
    }
    return true;
}

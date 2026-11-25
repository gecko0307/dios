module dios.core.ramfs;

/**
 * The root file system: a tree that lives in RAM ("initramfs"). It is read-only except for
 * the directory /home, where files and directories can be created, changed, renamed and removed
 * (nothing survives a reboot).
 *
 * The bootloader loads one module, "rootfs.tar" (an ustar archive made by build.py), and
 * this file indexes it into a table of nodes. The data is not copied: a file node points
 * into the archive (a file in /home that is written to gets its own copy first). Everything the system needs to start (/bin, /etc, ...) comes from
 * here, so nothing depends on a disk being present or on other boot modules.
 *
 * Disks are mounted below /mnt (see fs.d). /mnt and /home always exist, even when the archive
 * does not contain them, and when no archive was loaded the root holds only those two.
 *
 * File data written at run time lives in whole pages taken from the page allocator (paging.d),
 * contiguous per file; a file that grows is moved to a bigger run. The total is capped (see
 * RAMFS_MAX_PAGES) and the allocator always keeps RAMFS_RESERVE_PAGES free for programs.
 *
 * Paths given to the functions below are absolute and normalised ("/bin/gfxd.elf"),
 * as produced by fsResolve(). Names are case sensitive.
 */
import dios.bootloader.limine;
import dios.core.datetime;
import dios.core.exfat;
import dios.core.fat32w;
import dios.core.mem;
import dios.core.paging;
import dios.core.stdio;

enum uint RAMFS_MAX_NODES = 1024;
enum uint RAMFS_TAR_RESERVE = 256;          // nodes the archive cannot use: room for files made at run time
enum uint RAMFS_NAME_MAX = 64;
enum ulong RAMFS_MAX_PAGES = 16384;         // 64 MiB of file data written at run time
enum ulong RAMFS_RESERVE_PAGES = 4096;      // 16 MiB always left to the rest of the system

struct RamNode
{
    bool used;                  // false: free slot (a removed file or directory)
    bool owned;                 // the data is a run of pages of our own (else: inside the archive)
    uint gen;                   // bumped when the node is created or removed: tells open files it is gone
    ulong phys;                 // owned data: first page
    ulong capPages;             // owned data: pages in the run
    char[RAMFS_NAME_MAX] name;
    int parent;                 // node index, -1 for the root
    bool isDir;
    const(ubyte)* data;         // files: inside the archive
    ulong size;
    uint mtime;                 // DOS timestamp, 0 = unknown
}

__gshared RamNode[RAMFS_MAX_NODES] ramNodes;
__gshared uint ramNodeCount;
__gshared uint ramMntNode;      // the directory disks are mounted in
__gshared bool ramLoaded;
__gshared bool ramFullWarned;
__gshared uint ramHomeNode;     // /home
__gshared ulong ramUsedPages;   // pages held by files written at run time

extern(C):

/// The path names the root file system image (".../rootfs.tar").
bool ramfsIsImagePath(const(char)* path) @nogc nothrow
{
    uint n = 0;
    while (path[n] != 0)
        n++;
    const(char)* tail = "rootfs.tar";
    enum uint TAIL = 10;
    if (n < TAIL)
        return false;
    for (uint i = 0; i < TAIL; i++)
        if (path[n - TAIL + i] != tail[i])
            return false;
    return n == TAIL || path[n - TAIL - 1] == '/' || path[n - TAIL - 1] == ':';
}

ulong ramOctal(const(ubyte)* p, uint n) @nogc nothrow
{
    ulong v = 0;
    uint i = 0;
    while (i < n && p[i] == ' ')
        i++;
    for (; i < n && p[i] >= '0' && p[i] <= '7'; i++)
        v = (v << 3) | (p[i] - '0');
    return v;
}

/// Unix time -> DOS timestamp (the format the rest of the file system code uses). 0 if before 1980.
uint ramDosTime(ulong t) @nogc nothrow
{
    if (t == 0)
        return 0;
    long days = cast(long)(t / 86400);
    long rem = cast(long)(t % 86400);

    // civil date from days since 1970-01-01
    long z = days + 719468;
    long era = z / 146097;
    long doe = z - era * 146097;
    long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long y = yoe + era * 400;
    long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    long mp = (5 * doy + 2) / 153;
    long d = doy - (153 * mp + 2) / 5 + 1;
    long m = mp < 10 ? mp + 3 : mp - 9;
    if (m <= 2)
        y++;
    if (y < 1980 || y > 1980 + 127)
        return 0;

    long hour = rem / 3600;
    long min = (rem % 3600) / 60;
    long sec = rem % 60;
    return cast(uint)(((y - 1980) << 25) | (m << 21) | (d << 16) | (hour << 11) | (min << 5) | (sec / 2));
}

/// A new node. `runtime` is false while the archive is being indexed, which may not use up the
/// last RAMFS_TAR_RESERVE nodes. Freed slots are reused.
int ramNewNode(int parent, const(char)* name, uint len, bool isDir, bool runtime = true) @nogc nothrow
{
    uint idx = 0;
    for (uint i = 1; i < ramNodeCount; i++)
    {
        if (!ramNodes[i].used)
        {
            idx = i;
            break;
        }
    }
    if (idx == 0)
    {
        uint limit = runtime ? RAMFS_MAX_NODES : RAMFS_MAX_NODES - RAMFS_TAR_RESERVE;
        if (ramNodeCount >= limit)
        {
            if (!runtime && !ramFullWarned)
                kprintf("rootfs: too many files (max %u), the rest is ignored\n", limit);
            if (!runtime)
                ramFullWarned = true;
            return -1;
        }
        idx = ramNodeCount++;
    }
    RamNode* n = &ramNodes[idx];
    uint gen = n.gen + 1;
    *n = RamNode.init;
    n.gen = gen;
    n.used = true;
    for (uint i = 0; i < len; i++)
        n.name[i] = name[i];
    n.name[len] = 0;
    n.parent = parent;
    n.isDir = isDir;
    return cast(int)idx;
}

int ramFindChild(int parent, const(char)* name, uint len) @nogc nothrow
{
    for (uint i = 1; i < ramNodeCount; i++)
    {
        RamNode* n = &ramNodes[i];
        if (!n.used || n.parent != parent)
            continue;
        uint k = 0;
        while (k < len && n.name[k] == name[k])
            k++;
        if (k == len && n.name[k] == 0)
            return cast(int)i;
    }
    return -1;
}

/// Add `path` (as written in the archive: "./bin/x", "bin/x", "bin/") with its parent directories.
bool ramAddPath(const(char)* path, bool isDir, const(ubyte)* data, ulong size, uint mtime) @nogc nothrow
{
    int parent = 0;
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
        const(char)* q = p;
        while (*q == '/')
            q++;
        bool last = *q == 0;

        if (len == 1 && start[0] == '.')
            continue;
        if (len == 2 && start[0] == '.' && start[1] == '.')
            return false;
        if (len >= RAMFS_NAME_MAX)
        {
            kprintf("rootfs: name too long, skipped: %s\n", path);
            return false;
        }

        int child = ramFindChild(parent, start, len);
        if (last && !isDir)
        {
            if (child >= 0)
                return false;                       // duplicate
            child = ramNewNode(parent, start, len, false, false);
            if (child < 0)
                return false;
            ramNodes[child].data = data;
            ramNodes[child].size = size;
            ramNodes[child].mtime = mtime;
            return true;
        }

        if (child < 0)
        {
            child = ramNewNode(parent, start, len, true, false);
            if (child < 0)
                return false;
        }
        else if (!ramNodes[child].isDir)
            return false;                           // a file where a directory is needed

        if (last)
        {
            if (mtime != 0)
                ramNodes[child].mtime = mtime;
            return true;
        }
        parent = child;
    }
}

/// Index an ustar archive that is already in memory.
void ramfsParse(const(ubyte)* img, ulong size) @nogc nothrow
{
    ulong off = 0;
    uint files = 0;
    while (off + 512 <= size)
    {
        const(ubyte)* h = img + off;
        if (h[0] == 0)
            break;                                  // end of archive

        if (!(h[257] == 'u' && h[258] == 's' && h[259] == 't' && h[260] == 'a' && h[261] == 'r'))
        {
            kprintf("rootfs: bad tar header at offset %llu, stopping\n", off);
            break;
        }
        ulong sum = 0;
        for (uint i = 0; i < 512; i++)
            sum += (i >= 148 && i < 156) ? cast(ulong)' ' : h[i];
        if (sum != ramOctal(h + 148, 8))
        {
            kprintf("rootfs: bad tar checksum at offset %llu, stopping\n", off);
            break;
        }

        ulong fsize = ramOctal(h + 124, 12);
        uint mtime = ramDosTime(ramOctal(h + 136, 12));
        ubyte type = h[156];

        // path = prefix + "/" + name
        char[264] path;
        uint n = 0;
        if (h[345] != 0)
        {
            for (uint i = 0; i < 155 && h[345 + i] != 0; i++)
                path[n++] = cast(char)h[345 + i];
            path[n++] = '/';
        }
        for (uint i = 0; i < 100 && h[i] != 0; i++)
            path[n++] = cast(char)h[i];
        path[n] = 0;

        ulong dataOff = off + 512;
        if (type == '0' || type == 0)
        {
            if (dataOff + fsize > size)
            {
                kprintf("rootfs: archive is truncated at %s\n", path.ptr);
                break;
            }
            if (ramAddPath(path.ptr, false, img + dataOff, fsize, mtime))
                files++;
            off = dataOff + ((fsize + 511) & ~511UL);
        }
        else
        {
            if (type == '5')
                ramAddPath(path.ptr, true, null, 0, mtime);
            // links, devices, pax/GNU extension headers: not supported, skipped
            off = dataOff + ((fsize + 511) & ~511UL);
        }
    }
    kprintf("rootfs: %u file(s), %u node(s)\n", files, ramNodeCount);
}

/// Build the tree: the empty root plus /mnt, then whatever the "rootfs.tar" boot module holds.
void ramfsInit() @nogc nothrow
{
    ramNodeCount = 0;
    ramLoaded = false;
    ramFullWarned = false;
    ramUsedPages = 0;
    ramNewNode(-1, "", 0, true);                    // node 0: "/"
    ramNodes[0].used = true;

    if (moduleRequest.response !is null)
    {
        ulong n = moduleRequest.response.module_count;
        for (ulong i = 0; i < n; i++)
        {
            LimineFile* f = moduleRequest.response.modules[i];
            if (f is null || f.address is null || f.path is null || !ramfsIsImagePath(f.path))
                continue;
            ramfsParse(cast(const(ubyte)*)f.address, f.size);
            ramLoaded = true;
            break;
        }
    }
    if (!ramLoaded)
        kprintf("rootfs: no rootfs.tar boot module, the root directory is empty\n");

    int mnt = ramFindChild(0, "mnt", 3);
    if (mnt < 0)
        mnt = ramNewNode(0, "mnt", 3, true);
    ramMntNode = mnt < 0 ? 0 : cast(uint)mnt;

    int home = ramFindChild(0, "home", 4);
    if (home < 0)
        home = ramNewNode(0, "home", 4, true);
    ramHomeNode = home < 0 ? 0 : cast(uint)home;
}

/// Node of the absolute, normalised `path`, or -1.
int ramfsFind(const(char)* path) @nogc nothrow
{
    int node = 0;
    const(char)* p = path;
    for (;;)
    {
        while (*p == '/')
            p++;
        if (*p == 0)
            return node;
        const(char)* start = p;
        while (*p != 0 && *p != '/')
            p++;
        if (!ramNodes[node].isDir)
            return -1;
        node = ramFindChild(node, start, cast(uint)(p - start));
        if (node < 0)
            return -1;
    }
}

/// Describe node `node` the way the disk file systems describe their entries. The node
/// number travels in `firstCluster`, so exfatOpen() and the file code keep working.
void ramfsFillEntry(uint node, ExfatEntry* e) @nogc nothrow
{
    RamNode* n = &ramNodes[node];
    *e = ExfatEntry.init;
    uint i = 0;
    while (n.name[i] != 0)
    {
        e.name[i] = n.name[i];
        i++;
    }
    e.name[i] = 0;
    e.isDir = n.isDir;
    e.attrs = n.isDir ? EXFAT_ATTR_DIR : 0;
    e.noChain = false;
    e.firstCluster = node;
    e.size = n.size;
    e.validSize = n.size;
    e.mtime = n.mtime;
}

/// Call `fn` for every child of directory node `dir`. `stopped` tells whether `fn` ended the walk.
void ramfsIterate(uint dir, ExfatDirFn fn, void* ctx, bool* stopped) @nogc nothrow
{
    *stopped = false;
    for (uint i = 1; i < ramNodeCount; i++)
    {
        if (!ramNodes[i].used || ramNodes[i].parent != cast(int)dir)
            continue;
        ExfatEntry e;
        ramfsFillEntry(i, &e);
        if (!fn(&e, ctx))
        {
            *stopped = true;
            return;
        }
    }
}

ulong ramfsRead(uint node, ulong offset, void* dst, ulong len) @nogc nothrow
{
    if (node >= ramNodeCount || !ramNodes[node].used || ramNodes[node].isDir)
        return 0;
    RamNode* n = &ramNodes[node];
    if (offset >= n.size)
        return 0;
    if (len > n.size - offset)
        len = n.size - offset;
    memcpy(dst, n.data + offset, cast(size_t)len);
    return len;
}

// ---------------------------------------------------------------------------
// writing (below /home only; fs.d checks the path)
// ---------------------------------------------------------------------------

/// `path` (absolute, normalised) is inside /home, not /home itself.
bool ramfsWritablePath(const(char)* path) @nogc nothrow
{
    const(char)* h = "/home/";
    for (uint i = 0; i < 6; i++)
        if (path[i] != h[i])
            return false;
    return path[6] != 0;
}

/// Open files remember (node, gen): the node may be removed and its slot reused.
uint ramfsGeneration(uint node) @nogc nothrow
{
    return node < ramNodeCount ? ramNodes[node].gen : 0;
}

bool ramfsNodeLive(uint node, uint gen) @nogc nothrow
{
    return node < ramNodeCount && ramNodes[node].used && ramNodes[node].gen == gen;
}

ulong ramfsPagesUsed() @nogc nothrow
{
    return ramUsedPages;
}

bool ramNameOk(const(char)* name, uint len) @nogc nothrow
{
    if (len == 0 || len >= RAMFS_NAME_MAX)
        return false;
    if (len == 1 && name[0] == '.')
        return false;
    if (len == 2 && name[0] == '.' && name[1] == '.')
        return false;
    for (uint i = 0; i < len; i++)
        if (cast(ubyte)name[i] < 32 || name[i] == '/' || name[i] == 127)
            return false;
    return true;
}

uint ramDosNow() @nogc nothrow
{
    return fwDosNow();
}

/// Create a file or directory `name` in directory `parent`. Returns the node, or a negative FW_ERR_*.
int ramfsCreate(uint parent, const(char)* name, bool isDir) @nogc nothrow
{
    if (parent >= ramNodeCount || !ramNodes[parent].used || !ramNodes[parent].isDir)
        return FW_ERR_NOT_DIR;
    uint len = 0;
    while (name[len] != 0)
        len++;
    if (!ramNameOk(name, len))
        return FW_ERR_BAD_NAME;
    if (ramFindChild(cast(int)parent, name, len) >= 0)
        return FW_ERR_EXISTS;
    int node = ramNewNode(cast(int)parent, name, len, isDir);
    if (node < 0)
        return FW_ERR_NO_SPACE;
    ramNodes[node].mtime = ramDosNow();
    return node;
}

/// Node of the child `name` of `parent`, or -1.
int ramfsChild(uint parent, const(char)* name) @nogc nothrow
{
    uint len = 0;
    while (name[len] != 0)
        len++;
    return ramFindChild(cast(int)parent, name, len);
}

void ramFreeData(RamNode* n) @nogc nothrow
{
    if (n.owned)
    {
        pmmFreePages(n.phys, n.capPages);
        ramUsedPages -= n.capPages;
    }
    n.owned = false;
    n.phys = 0;
    n.capPages = 0;
    n.data = null;
}

/// Remove a file, or an empty directory.
int ramfsRemove(uint node) @nogc nothrow
{
    if (node == 0 || node >= ramNodeCount || !ramNodes[node].used || node == ramHomeNode || node == ramMntNode)
        return FW_ERR_INVALID;
    RamNode* n = &ramNodes[node];
    if (n.isDir)
    {
        for (uint i = 1; i < ramNodeCount; i++)
            if (ramNodes[i].used && ramNodes[i].parent == cast(int)node)
                return FW_ERR_NOT_EMPTY;
    }
    ramFreeData(n);
    n.size = 0;
    n.gen++;
    n.used = false;
    return FW_OK;
}

/// Move/rename `node` to `newName` in directory `newParent`. The caller has checked that a
/// directory does not move into itself.
int ramfsRename(uint node, uint newParent, const(char)* newName) @nogc nothrow
{
    if (node == 0 || node >= ramNodeCount || !ramNodes[node].used || node == ramHomeNode || node == ramMntNode)
        return FW_ERR_INVALID;
    if (newParent >= ramNodeCount || !ramNodes[newParent].used || !ramNodes[newParent].isDir)
        return FW_ERR_NOT_DIR;
    uint len = 0;
    while (newName[len] != 0)
        len++;
    if (!ramNameOk(newName, len))
        return FW_ERR_BAD_NAME;
    if (ramFindChild(cast(int)newParent, newName, len) >= 0)
        return FW_ERR_EXISTS;
    RamNode* n = &ramNodes[node];
    for (uint i = 0; i < len; i++)
        n.name[i] = newName[i];
    n.name[len] = 0;
    n.parent = cast(int)newParent;
    return FW_OK;
}

/// Make room for `newSize` bytes in a node's own pages (copying the archive data on first use).
bool ramEnsure(RamNode* n, ulong newSize) @nogc nothrow
{
    ulong need = (newSize + 4095) / 4096;
    if (need == 0)
        need = 1;
    if (n.owned && n.capPages >= need)
        return true;

    ulong cap = need;
    if (n.owned)
    {
        ulong grown = n.capPages * 2;
        if (grown > n.capPages + 512)
            grown = n.capPages + 512;               // large files: 2 MiB steps, not doubling
        if (grown > cap)
            cap = grown;
    }
    ulong held = n.owned ? n.capPages : 0;
    if (ramUsedPages - held + cap > RAMFS_MAX_PAGES)
    {
        cap = need;                                 // no slack, only what is needed
        if (ramUsedPages - held + cap > RAMFS_MAX_PAGES)
            return false;
    }
    if (pmmFreeCount() < cap + RAMFS_RESERVE_PAGES)
    {
        cap = need;
        if (pmmFreeCount() < cap + RAMFS_RESERVE_PAGES)
            return false;
    }

    ulong phys = pmmAllocContiguousZeroed(cap, 1, 0);
    if (phys == 0 && cap > need)
    {
        cap = need;
        phys = pmmAllocContiguousZeroed(cap, 1, 0);
    }
    if (phys == 0)
        return false;

    ubyte* fresh = cast(ubyte*)pmmPhysToVirt(phys);
    if (n.size != 0 && n.data !is null)
        memcpy(fresh, n.data, cast(size_t)n.size);
    ramFreeData(n);
    n.owned = true;
    n.phys = phys;
    n.capPages = cap;
    n.data = fresh;
    ramUsedPages += cap;
    return true;
}

/// Write at `offset` (at most the current size: no holes). Returns the bytes written or a
/// negative FW_ERR_*. Fewer bytes than asked mean the memory ran out.
long ramfsWrite(uint node, ulong offset, const(void)* src, ulong len) @nogc nothrow
{
    if (node == 0 || node >= ramNodeCount || !ramNodes[node].used)
        return FW_ERR_NOT_FOUND;
    RamNode* n = &ramNodes[node];
    if (n.isDir)
        return FW_ERR_IS_DIR;
    if (offset > n.size)
        return FW_ERR_INVALID;
    if (len == 0)
        return 0;
    if (len > 0xFFFFFFFFUL - offset)
        len = 0xFFFFFFFFUL - offset;                // same 4 GiB limit as FAT32

    ulong end = offset + len;
    if (!n.owned || end > n.capPages * 4096)
    {
        if (!ramEnsure(n, end))
        {
            // out of memory: write what fits in the pages we already have
            ulong room = n.owned ? n.capPages * 4096 : 0;
            if (offset >= room)
                return FW_ERR_NO_SPACE;
            len = room - offset;
            end = offset + len;
        }
    }
    memcpy(cast(ubyte*)n.data + offset, src, cast(size_t)len);
    if (end > n.size)
        n.size = end;
    n.mtime = ramDosNow();
    return cast(long)len;
}

/// Shorten a file (growing is not supported). Size 0 gives the memory back.
int ramfsTruncate(uint node, ulong size) @nogc nothrow
{
    if (node == 0 || node >= ramNodeCount || !ramNodes[node].used)
        return FW_ERR_NOT_FOUND;
    RamNode* n = &ramNodes[node];
    if (n.isDir)
        return FW_ERR_IS_DIR;
    if (size > n.size)
        return FW_ERR_INVALID;
    if (size == 0)
    {
        ramFreeData(n);
        n.data = null;
    }
    n.size = size;
    n.mtime = ramDosNow();
    return FW_OK;
}

bool ramfsNodeIsDir(uint node) @nogc nothrow
{
    return node < ramNodeCount && ramNodes[node].used && ramNodes[node].isDir;
}

ulong ramfsNodeSize(uint node) @nogc nothrow
{
    return node < ramNodeCount ? ramNodes[node].size : 0;
}

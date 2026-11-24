module dios.core.ramfs;

/**
 * The root file system: a read-only tree that lives in RAM ("initramfs").
 *
 * The bootloader loads one module, "rootfs.tar" (an ustar archive made by build.py), and
 * this file indexes it into a table of nodes. The data is not copied: a file node points
 * into the archive. Everything the system needs to start (/bin, /etc, ...) comes from
 * here, so nothing depends on a disk being present or on other boot modules.
 *
 * Disks are mounted below /mnt (see fs.d). /mnt always exists, even when the archive
 * does not contain it, and when no archive was loaded the root holds only /mnt.
 *
 * Paths given to the functions below are absolute and normalised ("/bin/gfxd.elf"),
 * as produced by fsResolve(). Names are case sensitive.
 */
import dios.bootloader.limine;
import dios.core.exfat;
import dios.core.mem;
import dios.core.stdio;

enum uint RAMFS_MAX_NODES = 512;
enum uint RAMFS_NAME_MAX = 64;

struct RamNode
{
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

int ramNewNode(int parent, const(char)* name, uint len, bool isDir) @nogc nothrow
{
    if (ramNodeCount >= RAMFS_MAX_NODES)
    {
        if (!ramFullWarned)
            kprintf("rootfs: too many files (max %u), the rest is ignored\n", RAMFS_MAX_NODES);
        ramFullWarned = true;
        return -1;
    }
    uint idx = ramNodeCount++;
    RamNode* n = &ramNodes[idx];
    for (uint i = 0; i < len; i++)
        n.name[i] = name[i];
    n.name[len] = 0;
    n.parent = parent;
    n.isDir = isDir;
    n.data = null;
    n.size = 0;
    n.mtime = 0;
    return cast(int)idx;
}

int ramFindChild(int parent, const(char)* name, uint len) @nogc nothrow
{
    for (uint i = 1; i < ramNodeCount; i++)
    {
        RamNode* n = &ramNodes[i];
        if (n.parent != parent)
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
            child = ramNewNode(parent, start, len, false);
            if (child < 0)
                return false;
            ramNodes[child].data = data;
            ramNodes[child].size = size;
            ramNodes[child].mtime = mtime;
            return true;
        }

        if (child < 0)
        {
            child = ramNewNode(parent, start, len, true);
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
    ramNewNode(-1, "", 0, true);                    // node 0: "/"

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
        if (ramNodes[i].parent != cast(int)dir)
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
    if (node >= ramNodeCount || ramNodes[node].isDir)
        return 0;
    RamNode* n = &ramNodes[node];
    if (offset >= n.size)
        return 0;
    if (len > n.size - offset)
        len = n.size - offset;
    memcpy(dst, n.data + offset, cast(size_t)len);
    return len;
}

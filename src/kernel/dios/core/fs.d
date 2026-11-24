module dios.core.fs;

/**
 * Mounted volumes (exFAT / FAT32, read-only) and path handling for the shell and
 * for user programs.
 *
 * Several volumes can be mounted at the same time. "/" is a virtual directory that
 * only lists the mount points; each volume appears under its own name:
 *
 *     /usb0p1/hello.elf        first partition of the first USB disk
 *     /MYSTICK/docs/a.txt      a volume mounted with `mount N MYSTICK`
 *
 * Every mount has its own generation counter, so unplugging or unmounting one volume
 * invalidates only the open files that live on it.
 */
import dios.core.blockdev;
import dios.core.exfat;
import dios.core.fat32;
import dios.core.stdio;

enum uint FS_PATH_MAX = 256;
enum uint FS_MAX_MOUNTS = 8;
enum uint FS_NAME_MAX = 32;

enum int FS_ROOT = -1;                  // "mount index" of the virtual root directory

// Results of fsMountPartition()
enum int FS_ERR_UNREADABLE = -1;        // not an exFAT or FAT32 volume
enum int FS_ERR_BAD_PARTITION = -2;
enum int FS_ERR_ALREADY = -3;           // that partition is already mounted
enum int FS_ERR_NO_SLOT = -4;
enum int FS_ERR_BAD_NAME = -5;          // empty, too long, or contains '/'
enum int FS_ERR_NAME_TAKEN = -6;

struct Mount
{
    bool mounted;
    uint partition;             // index into partitions
    uint generation;            // bumped on unmount: open files of an older mount are dead
    char[FS_NAME_MAX] name;     // mount point: "/name"
    ExfatVolume vol;
}

__gshared Mount[FS_MAX_MOUNTS] mounts;
__gshared char[FS_PATH_MAX] fsCwd;           // absolute, "/" when empty (see fsInitCwd)

extern(C):

/// Make sure the current directory holds a valid path.
void fsInitCwd() @nogc nothrow
{
    if (fsCwd[0] != '/')
    {
        fsCwd[0] = '/';
        fsCwd[1] = 0;
    }
}

uint fsMountCount() @nogc nothrow
{
    uint n = 0;
    for (uint i = 0; i < FS_MAX_MOUNTS; i++)
        if (mounts[i].mounted)
            n++;
    return n;
}

/// Mount slot holding partition `index`, or -1.
int fsMountOfPartition(uint index) @nogc nothrow
{
    for (uint i = 0; i < FS_MAX_MOUNTS; i++)
        if (mounts[i].mounted && mounts[i].partition == index)
            return cast(int)i;
    return -1;
}

bool fsNameEq(const(char)* a, const(char)* b) @nogc nothrow
{
    while (*a != 0 && *a == *b)
    {
        a++;
        b++;
    }
    return *a == *b;
}

/// Mount slot called `name` (compared up to `len` characters), or -1.
int fsFindMountLen(const(char)* name, uint len) @nogc nothrow
{
    for (uint i = 0; i < FS_MAX_MOUNTS; i++)
    {
        if (!mounts[i].mounted)
            continue;
        uint k = 0;
        while (k < len && mounts[i].name[k] == name[k] && name[k] != 0)
            k++;
        if (k == len && mounts[i].name[k] == 0)
            return cast(int)i;
    }
    return -1;
}

int fsFindMount(const(char)* name) @nogc nothrow
{
    uint len = 0;
    while (name[len] != 0)
        len++;
    return fsFindMountLen(name, len);
}

bool fsNameValid(const(char)* name) @nogc nothrow
{
    uint n = 0;
    while (name[n] != 0)
    {
        if (name[n] == '/' || name[n] <= ' ')
            return false;
        n++;
    }
    if (n == 0 || n >= FS_NAME_MAX)
        return false;
    if (n == 1 && name[0] == '.')
        return false;
    if (n == 2 && name[0] == '.' && name[1] == '.')
        return false;
    return true;
}

// "usb0" + partition 1 -> "usb0p1"; adds a digit suffix while the name is taken.
void fsDefaultName(uint partIndex, char* out_) @nogc nothrow
{
    Partition* p = &partitions[partIndex];
    uint n = 0;
    const(char)* dev = blockDevs[p.dev].name.ptr;
    while (dev[n] != 0 && n < FS_NAME_MAX - 8)
    {
        out_[n] = dev[n];
        n++;
    }
    out_[n++] = 'p';
    uint num = p.number;
    if (num >= 10)
        out_[n++] = cast(char)('0' + (num / 10) % 10);
    out_[n++] = cast(char)('0' + num % 10);
    out_[n] = 0;

    uint base = n;
    for (uint suffix = 2; fsFindMount(out_) >= 0 && suffix < 10; suffix++)
    {
        out_[base] = '_';
        out_[base + 1] = cast(char)('0' + suffix);
        out_[base + 2] = 0;
    }
}

/// Mount partition `index` (of `partitions`) as "/name" (`name` may be null or empty for
/// the default "usb0p1"). Returns the mount slot, or one of the FS_ERR_* codes.
int fsMountPartition(uint index, const(char)* name = null) @nogc nothrow
{
    if (index >= partitionCount || !partitions[index].valid)
        return FS_ERR_BAD_PARTITION;
    if (fsMountOfPartition(index) >= 0)
        return FS_ERR_ALREADY;

    char[FS_NAME_MAX] chosen;
    if (name is null || name[0] == 0)
        fsDefaultName(index, chosen.ptr);
    else
    {
        if (!fsNameValid(name))
            return FS_ERR_BAD_NAME;
        uint i = 0;
        while (name[i] != 0)
        {
            chosen[i] = name[i];
            i++;
        }
        chosen[i] = 0;
        if (fsFindMount(chosen.ptr) >= 0)
            return FS_ERR_NAME_TAKEN;
    }

    uint slot = 0;
    while (slot < FS_MAX_MOUNTS && mounts[slot].mounted)
        slot++;
    if (slot == FS_MAX_MOUNTS)
        return FS_ERR_NO_SLOT;

    Partition* p = &partitions[index];
    Mount* m = &mounts[slot];
    ExfatVolume* v = &m.vol;
    if (!exfatMount(v, &blockDevs[p.dev], p.startLba, p.sectors) &&
        !fat32Mount(v, &blockDevs[p.dev], p.startLba, p.sectors))
        return FS_ERR_UNREADABLE;

    uint k = 0;
    while (chosen[k] != 0)
    {
        m.name[k] = chosen[k];
        k++;
    }
    m.name[k] = 0;
    m.partition = index;
    m.mounted = true;           // m.generation keeps counting across mounts of this slot
    fsInitCwd();
    return cast(int)slot;
}

/// If the current directory is inside mount `slot`, go back to "/".
void fsCwdLeave(int slot) @nogc nothrow
{
    const(char)* nm = mounts[slot].name.ptr;
    uint n = 0;
    while (nm[n] != 0)
        n++;
    if (fsCwd[0] == '/' && fsFindMountLen(fsCwd.ptr + 1, n) == slot &&
        (fsCwd[1 + n] == 0 || fsCwd[1 + n] == '/'))
    {
        fsCwd[0] = '/';
        fsCwd[1] = 0;
    }
}

/// Unmount slot `slot`. Open files on it become invalid.
void fsUnmount(int slot) @nogc nothrow
{
    if (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted)
        return;
    fsCwdLeave(slot);           // before the name is gone
    mounts[slot].mounted = false;
    mounts[slot].generation++;
}

/// Unmount every volume that lives on block device `dev` (it was unplugged). Returns how many.
uint fsUnmountDevice(uint dev) @nogc nothrow
{
    uint n = 0;
    for (uint i = 0; i < FS_MAX_MOUNTS; i++)
    {
        if (mounts[i].mounted && partitions[mounts[i].partition].dev == dev)
        {
            kprintf("Unmounted /%s\n", mounts[i].name.ptr);
            fsUnmount(cast(int)i);
            n++;
        }
    }
    return n;
}

/// Mount every partition that holds an exFAT or FAT32 volume and is not mounted yet.
/// Returns the number of volumes that were newly mounted.
uint fsAutoMount() @nogc nothrow
{
    fsInitCwd();
    uint added = 0;
    for (uint i = 0; i < partitionCount; i++)
    {
        if (!partitions[i].valid || fsMountOfPartition(i) >= 0)
            continue;
        int slot = fsMountPartition(i);
        if (slot < 0)
            continue;
        Mount* m = &mounts[slot];
        Partition* p = &partitions[i];
        kprintf("Mounted %s volume '%s' (%s partition %u) as /%s\n",
                m.vol.fat32 ? "FAT32".ptr : "exFAT".ptr, m.vol.label.ptr,
                blockDevs[p.dev].name.ptr, cast(uint)p.number, m.name.ptr);
        added++;
    }
    return added;
}

// Append the components of `src` to the normalised path in `out` ("/a/b", no
// trailing slash, "/" is the empty string), resolving "." and "..". False on overflow.
bool fsPush(char* out_, uint* len, const(char)* src) @nogc nothrow
{
    while (*src != 0)
    {
        while (*src == '/')
            src++;
        if (*src == 0)
            break;

        const(char)* start = src;
        while (*src != 0 && *src != '/')
            src++;
        uint n = cast(uint)(src - start);

        if (n == 1 && start[0] == '.')
            continue;
        if (n == 2 && start[0] == '.' && start[1] == '.')
        {
            while (*len > 0 && out_[*len - 1] != '/')
                (*len)--;
            if (*len > 0)
                (*len)--;               // and the slash in front of that component
            continue;
        }

        if (*len + 1 + n + 1 > FS_PATH_MAX)
            return false;
        out_[(*len)++] = '/';
        for (uint i = 0; i < n; i++)
            out_[(*len)++] = start[i];
    }
    return true;
}

/// Absolute, normalised version of `path` (relative paths start at the current directory).
bool fsResolve(const(char)* path, char* out_) @nogc nothrow
{
    uint len = 0;
    if (path[0] != '/' && fsCwd[0] != 0 && !fsPush(out_, &len, fsCwd.ptr))
        return false;
    if (!fsPush(out_, &len, path))
        return false;
    if (len == 0)
        out_[len++] = '/';
    out_[len] = 0;
    return true;
}

/// Look up `path` (relative to the current directory). On success `mountOut` (if given)
/// receives the mount slot the entry lives on, or FS_ROOT for the virtual root "/".
bool fsStat(const(char)* path, ExfatEntry* e, int* mountOut = null) @nogc nothrow
{
    char[FS_PATH_MAX] full;
    if (!fsResolve(path, full.ptr))
        return false;

    if (full[1] == 0)                   // "/": the directory of mount points
    {
        *e = ExfatEntry.init;
        e.name[0] = 0;
        e.isDir = true;
        e.attrs = EXFAT_ATTR_DIR;
        if (mountOut !is null)
            *mountOut = FS_ROOT;
        return true;
    }

    const(char)* rest = full.ptr + 1;
    while (*rest != 0 && *rest != '/')
        rest++;
    int slot = fsFindMountLen(full.ptr + 1, cast(uint)(rest - (full.ptr + 1)));
    if (slot < 0)
        return false;
    if (!exfatLookup(&mounts[slot].vol, rest, e))
        return false;
    if (mountOut !is null)
        *mountOut = slot;
    return true;
}

// Entries of the virtual root: one directory per mount.
bool fsIterateRoot(ExfatDirFn fn, void* ctx) @nogc nothrow
{
    for (uint i = 0; i < FS_MAX_MOUNTS; i++)
    {
        if (!mounts[i].mounted)
            continue;
        ExfatEntry e = ExfatEntry.init;
        uint k = 0;
        while (mounts[i].name[k] != 0)
        {
            e.name[k] = mounts[i].name[k];
            k++;
        }
        e.name[k] = 0;
        e.isDir = true;
        e.attrs = EXFAT_ATTR_DIR;
        if (!fn(&e, ctx))
            return true;
    }
    return true;
}

/// Walk directory `dir` of mount `slot` (FS_ROOT: the list of mount points).
bool fsIterate(int slot, const(ExfatEntry)* dir, ExfatDirFn fn, void* ctx) @nogc nothrow
{
    if (slot == FS_ROOT)
        return fsIterateRoot(fn, ctx);
    if (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted)
        return false;
    return exfatIterate(&mounts[slot].vol, dir, fn, ctx);
}

/// Read from a file that lives on mount `slot`.
ulong fsRead(int slot, ExfatFile* f, ulong offset, void* dst, ulong len) @nogc nothrow
{
    if (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted)
        return 0;
    return exfatRead(&mounts[slot].vol, f, offset, dst, len);
}

/// Change the current directory. False if `path` is not a directory.
bool fsChdir(const(char)* path) @nogc nothrow
{
    char[FS_PATH_MAX] full;
    ExfatEntry e;
    if (!fsResolve(path, full.ptr) || !fsStat(full.ptr, &e) || !e.isDir)
        return false;
    uint i = 0;
    while (full[i] != 0)
    {
        fsCwd[i] = full[i];
        i++;
    }
    fsCwd[i] = 0;
    return true;
}

module dios.core.fs;

/**
 * The one mounted volume (exFAT, read-only) and path handling for the shell.
 *
 * There is a single root: "/" is the root directory of whichever volume was
 * mounted, at boot (first exFAT partition found) or later with `mount N`.
 */
import dios.core.blockdev;
import dios.core.exfat;
import dios.core.fat32;
import dios.core.stdio;

enum uint FS_PATH_MAX = 256;

struct Mount
{
    bool mounted;
    uint partition;             // index into partitions
    ExfatVolume vol;
}

__gshared Mount rootMount;
__gshared char[FS_PATH_MAX] fsCwd;           // set when a volume is mounted

extern(C):

/// Mount partition `index` (of `partitions`) as "/". Returns false if it is neither exFAT nor FAT32.
bool fsMountPartition(uint index) @nogc nothrow
{
    if (index >= partitionCount || !partitions[index].valid)
        return false;
    Partition* p = &partitions[index];

    ExfatVolume* v = &rootMount.vol;
    if (!exfatMount(v, &blockDevs[p.dev], p.startLba, p.sectors) &&
        !fat32Mount(v, &blockDevs[p.dev], p.startLba, p.sectors))
        return false;

    rootMount.mounted = true;
    rootMount.partition = index;
    fsCwd[0] = '/';
    fsCwd[1] = 0;
    return true;
}

/// Mount the first partition that holds an exFAT or FAT32 volume.
bool fsAutoMount() @nogc nothrow
{
    for (uint i = 0; i < partitionCount; i++)
    {
        if (fsMountPartition(i))
        {
            Partition* p = &partitions[i];
            kprintf("Mounted %s volume '%s' (%s partition %u) as /\n",
                    rootMount.vol.fat32 ? "FAT32".ptr : "exFAT".ptr, rootMount.vol.label.ptr, blockDevs[p.dev].name.ptr, cast(uint)p.number);
            return true;
        }
    }
    return false;
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
    if (path[0] != '/' && !fsPush(out_, &len, fsCwd.ptr))
        return false;
    if (!fsPush(out_, &len, path))
        return false;
    if (len == 0)
        out_[len++] = '/';
    out_[len] = 0;
    return true;
}

/// Look up `path` (relative to the current directory) on the mounted volume.
bool fsStat(const(char)* path, ExfatEntry* e) @nogc nothrow
{
    if (!rootMount.mounted)
        return false;
    char[FS_PATH_MAX] full;
    if (!fsResolve(path, full.ptr))
        return false;
    return exfatLookup(&rootMount.vol, full.ptr, e);
}

/// Change the current directory. False if `path` is not a directory.
bool fsChdir(const(char)* path) @nogc nothrow
{
    char[FS_PATH_MAX] full;
    ExfatEntry e;
    if (!rootMount.mounted || !fsResolve(path, full.ptr) || !exfatLookup(&rootMount.vol, full.ptr, &e) || !e.isDir)
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

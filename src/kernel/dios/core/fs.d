module dios.core.fs;

/**
 * The file system tree: a read-only root in RAM (ramfs.d, loaded from rootfs.tar by the
 * bootloader) with exFAT / FAT32 volumes mounted below /mnt.
 *
 *     /bin/gfxd.elf            from the root file system image
 *     /mnt/usb0p1/hello.elf   first partition of the first USB disk
 *     /mnt/MYSTICK/docs/a.txt a volume mounted with `mount N MYSTICK`
 *
 * Several volumes can be mounted at once. /mnt is a real directory of the root; listing it
 * also shows the mount points. Every mount has its own generation counter, so unplugging
 * or unmounting one volume invalidates only the open files that live on it. The root
 * itself can never go away.
 *
 * The root can be moved to a volume with `rmount` (fsSetRoot): "/" is then the root directory of
 * that volume and the initial RAM file system is only reachable again through `rmount ramfs`.
 * /mnt stays the kernel's own directory whatever the root is: it lists the mount points, and a
 * "mnt" directory on the root volume is hidden behind it. The root volume is an ordinary mount,
 * so it also shows up as /mnt/NAME, but paths are always normalised to the short form ("/a", never
 * "/mnt/NAME/a"), so one file never has two names.
 *
 * Volumes are mounted read-only. A FAT32 volume can be mounted (or remounted) for writing;
 * the root file system and exFAT volumes are always read-only. The write calls below
 * (fsOpenWrite, fsCreate, fsUnlink, ...) return FW_OK or one of the FW_ERR_* codes.
 */
import dios.core.blockdev;
import dios.core.exfat;
import dios.core.fat32;
import dios.core.fat32w;
import dios.core.ramfs;
import dios.core.stdio;

enum uint FS_PATH_MAX = 256;
enum uint FS_MAX_MOUNTS = 8;
enum uint FS_NAME_MAX = 32;

enum int FS_ROOT = -1;                  // "mount index" of files in the initial RAM file system (ramfs)
enum int FS_NONE = -2;                  // fsLocate(): below /mnt, but no such mount: nothing lives there
enum int FS_CWD_ALL = -100;             // for FsCwdLeaveHook: every task goes back to "/" (the root changed)
enum uint FS_MNT_CLUSTER = 0xFFFFFFFF;  // firstCluster of the virtual /mnt of a volume root (never a real cluster)

// Results of fsMountPartition()
enum int FS_ERR_UNREADABLE = -1;        // not an exFAT or FAT32 volume
enum int FS_ERR_BAD_PARTITION = -2;
enum int FS_ERR_ALREADY = -3;           // that partition is already mounted
enum int FS_ERR_NO_SLOT = -4;
enum int FS_ERR_BAD_NAME = -5;          // empty, too long, or contains '/'
enum int FS_ERR_NAME_TAKEN = -6;
enum int FS_ERR_NO_WRITE = -7;          // only FAT32 volumes can be mounted for writing
enum int FS_ERR_IO = -8;
enum int FS_ERR_NOT_MOUNTED = -9;       // fsSetRoot(): that mount slot is not in use

// open flags (Linux values, as in ulib): access mode in the low bits
enum uint FS_O_ACCMODE = 3;             // 0 = read only, 1 = write only, 2 = read/write
enum uint FS_O_CREATE = 0x40;
enum uint FS_O_TRUNC = 0x200;
enum uint FS_O_APPEND = 0x400;

enum int FW_OK = 0;
enum int FW_ERR_IO = -1;
enum int FW_ERR_NOT_FOUND = -2;
enum int FW_ERR_EXISTS = -3;
enum int FW_ERR_NO_SPACE = -4;
enum int FW_ERR_BAD_NAME = -5;
enum int FW_ERR_NOT_EMPTY = -6;
enum int FW_ERR_IS_DIR = -7;
enum int FW_ERR_NOT_DIR = -8;
enum int FW_ERR_RO = -9;            // volume is not mounted for writing
enum int FW_ERR_INVALID = -10;

enum uint FW_MAX_SET = 22;          // 20 long name entries + the short entry + a terminator

struct Mount
{
    bool mounted;
    uint partition;             // index into partitions
    uint generation;            // bumped on unmount: open files of an older mount are dead
    char[FS_NAME_MAX] name;     // mount point: "/name"
    ExfatVolume vol;
}

__gshared Mount[FS_MAX_MOUNTS] mounts;
// What "/" is: FS_ROOT = the initial RAM file system (ramfs.d), otherwise the mount slot of the
// volume that was made the root with fsSetRoot().
__gshared int fsRootSlot = FS_ROOT;
// The current directory of the RUNNING task: absolute, "/" when empty (see fsInitCwd). Every task has
// its own (Task.cwd in proc.d); the scheduler swaps them in and out when it switches tasks.
__gshared char[FS_PATH_MAX] fsCwd;

/// Called when mount `slot` goes away, so that the owner of the other directories (proc.d) can
/// send the tasks whose current directory is inside it back to "/".
alias FsCwdLeaveHook = extern(C) void function(int slot) @nogc nothrow;
__gshared FsCwdLeaveHook fsCwdLeaveHook;

// Lists the root directory of the root volume with its own "mnt" replaced by the virtual one.
struct MntShim
{
    ExfatDirFn fn;
    void* ctx;
    bool stopped;
}

extern(C):

/// Build the root file system and start in "/".
void fsInit() @nogc nothrow
{
    ramfsInit();
    fsInitCwd();
}

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

/// Mount partition `index` (of `partitions`) as "/mnt/name" (`name` may be null or empty for
/// the default "usb0p1"), read-only unless `writable` (FAT32 only). Returns the mount slot, or one of the FS_ERR_* codes.
int fsMountPartition(uint index, const(char)* name = null, bool writable = false) @nogc nothrow
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
    if (writable)
    {
        if (!v.fat32)
            return FS_ERR_NO_WRITE;
        if (fat32SetWritable(v) != FW_OK)
            return FS_ERR_IO;
    }

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

// ---- Volume ID ----------------------------------------------------------------------------
// The serial number every exFAT / FAT32 volume has in its boot sector, written like Windows
// does: "1A2B-3C4D". It stays the same when the volume's mount name, partition number or disk
// changes, which makes it a stable way to name a volume (rmount id=1A2B-3C4D).

__gshared ubyte[4096] fsProbeBuf;       // boot sector of a volume that is not mounted

int fsHexDigit(char c) @nogc nothrow
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

/// "1A2B-3C4D", "1a2b3c4d" or "0x1A2B3C4D" -> 32-bit ID. Exactly 8 hex digits, with at most one '-' after the fourth.
bool fsParseVolumeId(const(char)* s, uint* id) @nogc nothrow
{
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        s += 2;
    uint v = 0;
    uint digits = 0;
    bool dash = false;
    for (; *s != 0; s++)
    {
        if (*s == '-' && digits == 4 && !dash)
        {
            dash = true;
            continue;
        }
        int d = fsHexDigit(*s);
        if (d < 0 || digits == 8)
            return false;
        v = (v << 4) | cast(uint)d;
        digits++;
    }
    if (digits != 8)
        return false;
    *id = v;
    return true;
}

/// `out_` needs 10 bytes: "1A2B-3C4D" and the NUL.
void fsFormatVolumeId(uint id, char* out_) @nogc nothrow
{
    immutable char[16] hex = "0123456789ABCDEF";
    uint k = 0;
    for (int shift = 28; shift >= 0; shift -= 4)
    {
        out_[k++] = hex[(id >> shift) & 0xF];
        if (shift == 16)
            out_[k++] = '-';
    }
    out_[k] = 0;
}

bool fsBytesAre(const(ubyte)* b, const(char)* text, uint n) @nogc nothrow
{
    for (uint i = 0; i < n; i++)
        if (b[i] != cast(ubyte)text[i])
            return false;
    return true;
}

/// The ID of the exFAT / FAT32 volume in partition `index`. Mounted or not: an unmounted one
/// is recognised by its boot sector, so nothing has to be mounted just to look.
bool fsPartitionVolumeId(uint index, uint* id) @nogc nothrow
{
    if (index >= partitionCount || !partitions[index].valid)
        return false;
    int ms = fsMountOfPartition(index);
    if (ms >= 0)
    {
        *id = mounts[ms].vol.serial;
        return true;
    }
    Partition* p = &partitions[index];
    BlockDev* b = &blockDevs[p.dev];
    if (b.sectorSize > fsProbeBuf.length || !blockRead(b, p.startLba, 1, fsProbeBuf.ptr))
        return false;
    const(ubyte)* s = fsProbeBuf.ptr;
    uint at;
    if (fsBytesAre(s + 3, "EXFAT   ", 8))
        at = 100;                       // exFAT: VolumeSerialNumber
    else if (fsBytesAre(s + 82, "FAT32   ", 8))
        at = 67;                        // FAT32: BS_VolID
    else
        return false;
    *id = cast(uint)s[at] | (cast(uint)s[at + 1] << 8) | (cast(uint)s[at + 2] << 16) | (cast(uint)s[at + 3] << 24);
    return true;
}

/// Partition holding the volume with this ID, or -1. `count` = how many volumes have it:
/// a cloned disk or image repeats an ID, and then the ID names nothing for certain.
int fsFindPartitionByVolumeId(uint id, uint* count) @nogc nothrow
{
    int found = -1;
    uint n = 0;
    for (uint i = 0; i < partitionCount; i++)
    {
        uint other;
        if (fsPartitionVolumeId(i, &other) && other == id)
        {
            if (found < 0)
                found = cast(int)i;
            n++;
        }
    }
    *count = n;
    return found;
}

/// Mount slot of an absolute path below /mnt ("/mnt/NAME/..."), or -1. `rest` gets the
/// part after the mount name.
int fsMountOfPath(const(char)* full, const(char)** rest) @nogc nothrow
{
    if (!(full[0] == '/' && full[1] == 'm' && full[2] == 'n' && full[3] == 't' && full[4] == '/'))
        return -1;
    const(char)* name = full + 5;
    const(char)* end = name;
    while (*end != 0 && *end != '/')
        end++;
    int slot = fsFindMountLen(name, cast(uint)(end - name));
    if (slot >= 0)
        *rest = end;
    return slot;
}

/// Where does the absolute path `full` sit relative to the kernel's /mnt directory?
/// 0 = outside it, 1 = it is /mnt itself, 2 = below it.
uint fsMntClass(const(char)* full) @nogc nothrow
{
    if (!(full[0] == '/' && full[1] == 'm' && full[2] == 'n' && full[3] == 't'))
        return 0;
    if (full[4] == 0)
        return 1;
    return full[4] == '/' ? 2 : 0;
}

/// Which file system holds the absolute, normalised path `full`? Returns the mount slot of a
/// volume (`rest` = the path inside that volume: "" for its root directory, else "/a/b"), FS_ROOT
/// for the initial RAM file system, or FS_NONE for a place below /mnt that is no mount.
int fsLocate(const(char)* full, const(char)** rest) @nogc nothrow
{
    int slot = fsMountOfPath(full, rest);
    if (slot >= 0)
        return slot;
    if (fsRootSlot == FS_ROOT)
        return FS_ROOT;
    if (fsMntClass(full) != 0)
        return FS_NONE;                 // /mnt belongs to the kernel, not to the root volume
    *rest = (full[1] == 0) ? full + 1 : full;   // "/" -> ""
    return fsRootSlot;
}

/// The root volume is also mounted as /mnt/NAME. Both spellings name the same files, so make
/// the short one the only one ("/mnt/NAME/a/b" -> "/a/b"): code that compares paths (cd out of
/// a directory that is being removed, moving a directory into itself) keeps working.
void fsCanonRoot(char* path) @nogc nothrow
{
    if (fsRootSlot < 0)
        return;
    const(char)* rest;
    if (fsMountOfPath(path, &rest) != fsRootSlot)
        return;
    if (*rest == 0)
    {
        path[0] = '/';
        path[1] = 0;
        return;
    }
    uint n = 0;
    while (rest[n] != 0)                // rest lies inside path, ahead of what is written: copying forward is safe
    {
        path[n] = rest[n];
        n++;
    }
    path[n] = 0;
}

/// The directory entry of the virtual /mnt of a volume root.
void fsVirtualMntEntry(ExfatEntry* e) @nogc nothrow
{
    *e = ExfatEntry.init;
    e.name[0] = 'm';
    e.name[1] = 'n';
    e.name[2] = 't';
    e.name[3] = 0;
    e.isDir = true;
    e.attrs = EXFAT_ATTR_DIR;
    e.firstCluster = FS_MNT_CLUSTER;
}

bool fsIsMntName(const(char)* name) @nogc nothrow
{
    // FAT names are not case sensitive
    return (name[0] | 0x20) == 'm' && (name[1] | 0x20) == 'n' && (name[2] | 0x20) == 't' && name[3] == 0;
}

extern(C) bool fsMntShimCb(const(ExfatEntry)* e, void* ctx) @nogc nothrow
{
    MntShim* s = cast(MntShim*)ctx;
    if (fsIsMntName(e.name.ptr))
        return true;                    // hidden behind the virtual /mnt
    if (!s.fn(e, s.ctx))
    {
        s.stopped = true;
        return false;
    }
    return true;
}

/// Make mount slot `slot` (or, with FS_ROOT, the initial RAM file system) the root directory.
/// Open files stay open (they remember their own volume). The old current directories mean
/// nothing in the new tree, so every task goes back to "/". Returns `slot` or an FS_ERR_*.
int fsSetRoot(int slot) @nogc nothrow
{
    if (slot != FS_ROOT && (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted))
        return FS_ERR_NOT_MOUNTED;
    fsRootSlot = slot;
    fsCwd[0] = '/';
    fsCwd[1] = 0;
    if (fsCwdLeaveHook !is null)
        fsCwdLeaveHook(FS_CWD_ALL);
    return slot;
}

const(char)* fsMountErrorText(int err) @nogc nothrow
{
    switch (err)
    {
        case FS_ERR_ALREADY: return "that partition is already mounted";
        case FS_ERR_NO_SLOT: return "too many mounts (use 'umount NAME' first)";
        case FS_ERR_BAD_NAME: return "bad mount name";
        case FS_ERR_NAME_TAKEN: return "that mount name is already in use";
        case FS_ERR_BAD_PARTITION: return "no such partition";
        case FS_ERR_NO_WRITE: return "only FAT32 volumes can be mounted read-write";
        case FS_ERR_IO: return "I/O error while preparing the volume for writing";
        case FS_ERR_NOT_MOUNTED: return "that volume is not mounted";
        default: return "not a readable exFAT or FAT32 volume";
    }
}

/// If the current directory (of this task and of every other) is inside mount `slot`, go back to "/".
void fsCwdLeave(int slot) @nogc nothrow
{
    const(char)* rest;
    if (fsMountOfPath(fsCwd.ptr, &rest) == slot)
    {
        fsCwd[0] = '/';
        fsCwd[1] = 0;
    }
    if (fsCwdLeaveHook !is null)
        fsCwdLeaveHook(slot);
}

/// Unmount slot `slot`. Open files on it become invalid.
void fsUnmount(int slot) @nogc nothrow
{
    if (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted)
        return;
    if (slot == fsRootSlot)
    {
        // The root volume is going away (unplugged): fall back to the initial RAM file system.
        // (The `umount` command refuses this; it only happens when the disk itself vanishes.)
        kprintf("Root volume /mnt/%s is gone; the root is the initial RAM file system again\n", mounts[slot].name.ptr);
        fsSetRoot(FS_ROOT);
    }
    fsCwdLeave(slot);           // before the name is gone
    if (mounts[slot].vol.writable)
    {
        fat32Sync(&mounts[slot].vol, true);     // volume marked clean, device flushed
        mounts[slot].vol.writable = false;
    }
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
            kprintf("Unmounted /mnt/%s\n", mounts[i].name.ptr);
            mounts[i].vol.writable = false;     // the device is gone: nothing to sync
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
        kprintf("Mounted %s volume '%s' (%s partition %u) as /mnt/%s\n",
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
    fsCanonRoot(out_);
    return true;
}

/// Look up `path` (relative to the current directory). On success `mountOut` (if given)
/// receives the mount slot the entry lives on, or FS_ROOT for the root file system.
bool fsStat(const(char)* path, ExfatEntry* e, int* mountOut = null) @nogc nothrow
{
    char[FS_PATH_MAX] full;
    if (!fsResolve(path, full.ptr))
        return false;

    // With a volume as the root, /mnt is still the kernel's: it lists the mount points.
    if (fsRootSlot >= 0 && fsMntClass(full.ptr) == 1)
    {
        fsVirtualMntEntry(e);
        if (mountOut !is null)
            *mountOut = fsRootSlot;
        return true;
    }

    const(char)* rest;
    int slot = fsLocate(full.ptr, &rest);
    if (slot == FS_NONE)
        return false;
    if (slot >= 0)
    {
        if (!exfatLookup(&mounts[slot].vol, rest, e))
            return false;
        if (mountOut !is null)
            *mountOut = slot;
        return true;
    }

    int node = ramfsFind(full.ptr);
    if (node < 0)
        return false;
    ramfsFillEntry(cast(uint)node, e);
    if (mountOut !is null)
        *mountOut = FS_ROOT;
    return true;
}

// The volumes as directory entries: they show up when /mnt is listed.
void fsIterateMounts(ExfatDirFn fn, void* ctx) @nogc nothrow
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
            return;
    }
}

/// Walk directory `dir` that lives on mount `slot` (FS_ROOT: the root file system).
bool fsIterate(int slot, const(ExfatEntry)* dir, ExfatDirFn fn, void* ctx) @nogc nothrow
{
    if (slot == FS_ROOT)
    {
        bool stopped;
        ramfsIterate(dir.firstCluster, fn, ctx, &stopped);
        if (!stopped && dir.firstCluster == ramMntNode)
            fsIterateMounts(fn, ctx);
        return true;
    }
    if (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted)
        return false;
    if (slot == fsRootSlot)
    {
        if (dir.firstCluster == FS_MNT_CLUSTER)
        {
            fsIterateMounts(fn, ctx);       // the virtual /mnt
            return true;
        }
        if (dir.firstCluster == mounts[slot].vol.rootCluster)
        {
            // "/" of the root volume: its entries, with /mnt (virtual) in place of any "mnt" of its own
            MntShim shim;
            shim.fn = fn;
            shim.ctx = ctx;
            shim.stopped = false;
            bool ok = exfatIterate(&mounts[slot].vol, dir, &fsMntShimCb, &shim);
            if (ok && !shim.stopped)
            {
                ExfatEntry m;
                fsVirtualMntEntry(&m);
                fn(&m, ctx);
            }
            return ok;
        }
    }
    return exfatIterate(&mounts[slot].vol, dir, fn, ctx);
}

/// Read from a file that lives on mount `slot` (FS_ROOT: the root file system).
ulong fsRead(int slot, ExfatFile* f, ulong offset, void* dst, ulong len) @nogc nothrow
{
    if (slot == FS_ROOT)
        return ramfsRead(f.cur.firstCluster, offset, dst, len);
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

// ---------------------------------------------------------------------------
// writing
// ---------------------------------------------------------------------------

const(char)* fsErrorText(int err) @nogc nothrow
{
    switch (err)
    {
        case FW_OK: return "ok";
        case FW_ERR_IO: return "I/O error";
        case FW_ERR_NOT_FOUND: return "not found";
        case FW_ERR_EXISTS: return "already exists";
        case FW_ERR_NO_SPACE: return "no space left on the volume";
        case FW_ERR_BAD_NAME: return "invalid name (ASCII only, no \\ / : * ? \" < > |)";
        case FW_ERR_NOT_EMPTY: return "directory not empty";
        case FW_ERR_IS_DIR: return "is a directory";
        case FW_ERR_NOT_DIR: return "not a directory";
        case FW_ERR_RO: return "read-only (only /home and FAT32 volumes mounted with 'rw' can be changed)";
        default: return "invalid operation";
    }
}

/// Split `path` into the mount it lives on, its parent directory and the last name. Fails with
/// FW_ERR_RO unless the volume is FAT32 and mounted for writing, or the path is below /home of
/// the root file system. For FAT32 `parentFirst` is the parent's first cluster; for /home the
/// slot is FS_ROOT and `parentFirst` is the parent's ramfs node.
int fsPrepare(const(char)* path, int* slotOut, uint* parentFirst, char* leaf) @nogc nothrow
{
    char[FS_PATH_MAX] full;
    if (!fsResolve(path, full.ptr))
        return FW_ERR_BAD_NAME;

    const(char)* rest;
    int slot = fsLocate(full.ptr, &rest);
    if (slot == FS_NONE)
        return FW_ERR_RO;                       // /mnt is the kernel's own directory (see fsSetRoot)
    if (slot == FS_ROOT)
    {
        // the initial RAM file system: only /home can be changed
        if (!ramfsWritablePath(full.ptr))
            return FW_ERR_RO;
        uint n = 0;
        while (full[n] != 0)
            n++;
        uint c = n;
        while (c > 0 && full[c - 1] != '/')
            c--;
        // full[c - 1] is the '/' before the last name; ramfsWritablePath() guarantees c >= 6
        if (n - c == 0 || n - c > 255)
            return FW_ERR_INVALID;
        char[FS_PATH_MAX] dir;
        for (uint i = 0; i + 1 < c; i++)
            dir[i] = full[i];
        dir[c - 1] = 0;
        int pn = ramfsFind(dir.ptr);
        if (pn < 0)
            return FW_ERR_NOT_FOUND;
        if (!ramfsNodeIsDir(cast(uint)pn))
            return FW_ERR_NOT_DIR;
        for (uint i = 0; i < n - c; i++)
            leaf[i] = full[c + i];
        leaf[n - c] = 0;
        *slotOut = FS_ROOT;
        *parentFirst = cast(uint)pn;
        return FW_OK;
    }
    Mount* m = &mounts[slot];
    if (!m.vol.fat32 || !m.vol.writable)
        return FW_ERR_RO;

    uint len = 0;
    while (rest[len] != 0)
        len++;
    if (len == 0)
        return FW_ERR_INVALID;                  // the mount point itself

    uint cut = len;
    while (cut > 0 && rest[cut - 1] != '/')
        cut--;
    // rest[cut - 1] is the '/' before the last name; the parent is rest[0 .. cut - 1]
    if (cut == 0 || len - cut == 0 || len - cut > 255)
        return FW_ERR_INVALID;

    char[FS_PATH_MAX] parent;
    for (uint i = 0; i + 1 < cut; i++)
        parent[i] = rest[i];
    parent[cut - 1] = 0;

    ExfatEntry pe;
    if (!exfatLookup(&m.vol, parent.ptr, &pe))
        return FW_ERR_NOT_FOUND;
    if (!pe.isDir)
        return FW_ERR_NOT_DIR;

    for (uint i = 0; i < len - cut; i++)
        leaf[i] = rest[cut + i];
    leaf[len - cut] = 0;
    *slotOut = slot;
    *parentFirst = pe.firstCluster;
    return FW_OK;
}

/// Create an empty file or a directory.
int fsCreate(const(char)* path, bool isDir) @nogc nothrow
{
    int slot;
    uint parent;
    char[256] leaf;
    int r = fsPrepare(path, &slot, &parent, leaf.ptr);
    if (r != FW_OK)
        return r;
    if (slot == FS_ROOT)
    {
        int node = ramfsCreate(parent, leaf.ptr, isDir);
        return node < 0 ? node : FW_OK;
    }
    FwLoc loc;
    return fat32Create(&mounts[slot].vol, parent, leaf.ptr, isDir, &loc);
}

int fsUnlink(const(char)* path) @nogc nothrow
{
    int slot;
    uint parent;
    char[256] leaf;
    int r = fsPrepare(path, &slot, &parent, leaf.ptr);
    if (r != FW_OK)
        return r;
    if (slot == FS_ROOT)
    {
        int node = ramfsChild(parent, leaf.ptr);
        if (node < 0)
            return FW_ERR_NOT_FOUND;
        if (ramfsNodeIsDir(cast(uint)node))
            return FW_ERR_IS_DIR;
        return ramfsRemove(cast(uint)node);
    }
    return fat32Unlink(&mounts[slot].vol, parent, leaf.ptr);
}

int fsRmdir(const(char)* path) @nogc nothrow
{
    int slot;
    uint parent;
    char[256] leaf;
    int r = fsPrepare(path, &slot, &parent, leaf.ptr);
    if (r != FW_OK)
        return r;
    // never remove the directory the shell is standing in
    char[FS_PATH_MAX] full;
    if (fsResolve(path, full.ptr) && fsNameEq(full.ptr, fsCwd.ptr))
        return FW_ERR_INVALID;
    if (slot == FS_ROOT)
    {
        int node = ramfsChild(parent, leaf.ptr);
        if (node < 0)
            return FW_ERR_NOT_FOUND;
        if (!ramfsNodeIsDir(cast(uint)node))
            return FW_ERR_NOT_DIR;
        return ramfsRemove(cast(uint)node);
    }
    return fat32Rmdir(&mounts[slot].vol, parent, leaf.ptr);
}

int fsRename(const(char)* from, const(char)* to) @nogc nothrow
{
    char[FS_PATH_MAX] a;
    char[FS_PATH_MAX] b;
    if (!fsResolve(from, a.ptr) || !fsResolve(to, b.ptr))
        return FW_ERR_BAD_NAME;
    // a directory cannot move into itself
    uint n = 0;
    while (a[n] != 0 && a[n] == b[n])
        n++;
    if (a[n] == 0 && (b[n] == 0 || b[n] == '/'))
        return b[n] == 0 ? FW_ERR_EXISTS : FW_ERR_INVALID;

    int slotA, slotB;
    uint parentA, parentB;
    char[256] leafA;
    char[256] leafB;
    int r = fsPrepare(a.ptr, &slotA, &parentA, leafA.ptr);
    if (r != FW_OK)
        return r;
    r = fsPrepare(b.ptr, &slotB, &parentB, leafB.ptr);
    if (r != FW_OK)
        return r;
    if (slotA != slotB)
        return FW_ERR_INVALID;                  // moving between volumes: copy and remove instead
    if (slotA == FS_ROOT)
    {
        int node = ramfsChild(parentA, leafA.ptr);
        if (node < 0)
            return FW_ERR_NOT_FOUND;
        return ramfsRename(cast(uint)node, parentB, leafB.ptr);
    }
    return fat32Rename(&mounts[slotA].vol, parentA, leafA.ptr, parentB, leafB.ptr);
}

/// Open a file for writing: creates it with FS_O_CREATE, empties it with FS_O_TRUNC.
/// `e` gets the directory entry, `wf` the state for fsWriteFile().
int fsOpenWrite(const(char)* path, uint flags, int* slotOut, ExfatEntry* e, FwFile* wf) @nogc nothrow
{
    int slot;
    uint parent;
    char[256] leaf;
    int r = fsPrepare(path, &slot, &parent, leaf.ptr);
    if (r != FW_OK)
        return r;
    if (slot == FS_ROOT)
    {
        int node = ramfsChild(parent, leaf.ptr);
        if (node < 0)
        {
            if (!(flags & FS_O_CREATE))
                return FW_ERR_NOT_FOUND;
            node = ramfsCreate(parent, leaf.ptr, false);
            if (node < 0)
                return node;
        }
        else if (ramfsNodeIsDir(cast(uint)node))
            return FW_ERR_IS_DIR;
        if ((flags & FS_O_TRUNC) && ramfsTruncate(cast(uint)node, 0) != FW_OK)
            return FW_ERR_IO;
        ramfsFillEntry(cast(uint)node, e);
        *wf = FwFile.init;
        wf.firstCluster = cast(uint)node;       // the ramfs node, as in `e`
        wf.size = e.size;
        *slotOut = FS_ROOT;
        return FW_OK;
    }
    ExfatVolume* v = &mounts[slot].vol;

    FwItem it;
    r = fat32Lookup(v, parent, leaf.ptr, &it);
    if (r == FW_ERR_NOT_FOUND)
    {
        if (!(flags & FS_O_CREATE))
            return FW_ERR_NOT_FOUND;
        r = fat32Create(v, parent, leaf.ptr, false, &it.loc);
        if (r != FW_OK)
            return r;
        it.isDir = false;
        it.firstCluster = 0;
        it.size = 0;
    }
    else if (r != FW_OK)
        return r;
    else if (it.isDir)
        return FW_ERR_IS_DIR;

    *wf = FwFile.init;
    wf.loc = it.loc;
    wf.firstCluster = it.firstCluster;
    wf.size = it.size;
    if ((flags & FS_O_TRUNC) && wf.size != 0)
    {
        r = fat32Truncate(v, wf, 0);
        if (r != FW_OK)
            return r;
    }

    if (!fsStat(path, e))
        return FW_ERR_IO;
    e.firstCluster = wf.firstCluster;
    e.size = wf.size;
    e.validSize = wf.size;
    *slotOut = slot;
    return FW_OK;
}

/// Write to a file opened with fsOpenWrite(). Returns the bytes written or a negative FW_ERR_*.
long fsWriteFile(int slot, FwFile* wf, ulong offset, const(void)* src, ulong len) @nogc nothrow
{
    if (slot == FS_ROOT)
    {
        long n = ramfsWrite(wf.firstCluster, offset, src, len);
        if (n >= 0)
            wf.size = ramfsNodeSize(wf.firstCluster);
        return n;
    }
    if (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted)
        return FW_ERR_RO;
    return fat32WriteFile(&mounts[slot].vol, wf, offset, src, len);
}

/// Ask every writable volume to flush (the volumes stay marked "in use").
void fsSyncAll() @nogc nothrow
{
    for (uint i = 0; i < FS_MAX_MOUNTS; i++)
        if (mounts[i].mounted && mounts[i].vol.writable)
            fat32Sync(&mounts[i].vol, false);
}

/// Switch a mounted volume between read-write and read-only.
int fsRemount(int slot, bool writable) @nogc nothrow
{
    if (slot < 0 || slot >= cast(int)FS_MAX_MOUNTS || !mounts[slot].mounted)
        return FS_ERR_BAD_PARTITION;
    ExfatVolume* v = &mounts[slot].vol;
    if (writable)
    {
        if (!v.fat32)
            return FS_ERR_NO_WRITE;
        return fat32SetWritable(v) == FW_OK ? slot : FS_ERR_IO;
    }
    if (v.writable)
    {
        int r = fat32Sync(v, true);
        v.writable = false;
        if (r != FW_OK)
            return FS_ERR_IO;
    }
    return slot;
}

enum int FS_ROOT_NOT_FOUND = -1;

/// Find the first mounted partition containing an empty /boot/dios.here marker.
/// Returns the mount slot or FS_ROOT_NOT_FOUND.
int fsFindInstalledRoot() @nogc nothrow
{
    for (int i = 0; i < FS_MAX_MOUNTS; i++)
    {
        if (!mounts[i].mounted)
            continue;

        ExfatEntry e;

        if (exfatLookup(&mounts[i].vol, "/boot/dios.here", &e) &&
            !e.isDir && e.size == 0)
        {
            return i;
        }
    }

    return FS_ROOT_NOT_FOUND;
}

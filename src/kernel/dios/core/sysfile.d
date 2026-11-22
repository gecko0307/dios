module dios.core.sysfile;

/**
 * File system calls for user programs (read-only): a small table of open files
 * and directories on the mounted volume.
 *
 * Everything here works on kernel pointers; proc.d validates the user pointers
 * and copies the path strings before calling in.
 */
import dios.core.exfat;
import dios.core.fs;

enum uint SYSFILE_MAX_OPEN = 8;
enum long SYSFILE_EOF_ERR = -1;

// Layouts shared with user programs (see ulib.d)
struct UserStat
{
    ulong size;
    uint mtime;                 // DOS timestamp, same as the shell shows
    uint isDir;
}

struct UserDirent
{
    ulong size;
    uint mtime;
    uint isDir;
    char[EXFAT_NAME_MAX] name;
}

struct OpenFile
{
    bool used;
    bool isDir;
    ExfatEntry entry;
    ExfatFile file;
    ulong pos;                  // file offset, or the next directory index
}

__gshared OpenFile[SYSFILE_MAX_OPEN] openFiles;

struct DirPick
{
    ulong want;
    ulong seen;
    bool found;
    ExfatEntry entry;
}

extern(C):

void sysfileReset() @nogc nothrow
{
    for (uint i = 0; i < SYSFILE_MAX_OPEN; i++)
        openFiles[i].used = false;
}

OpenFile* sysfileGet(ulong fd) @nogc nothrow
{
    if (fd >= SYSFILE_MAX_OPEN || !openFiles[fd].used)
        return null;
    return &openFiles[fd];
}

/// Open a file or directory. Returns the descriptor, or -1.
long sysfileOpen(const(char)* path) @nogc nothrow
{
    if (!rootMount.mounted)
        return -1;
    uint fd = 0;
    while (fd < SYSFILE_MAX_OPEN && openFiles[fd].used)
        fd++;
    if (fd == SYSFILE_MAX_OPEN)
        return -1;

    OpenFile* f = &openFiles[fd];
    if (!fsStat(path, &f.entry))
        return -1;
    f.isDir = f.entry.isDir;
    f.pos = 0;
    if (!f.isDir && !exfatOpen(&f.file, &f.entry))
        return -1;
    f.used = true;
    return fd;
}

long sysfileClose(ulong fd) @nogc nothrow
{
    OpenFile* f = sysfileGet(fd);
    if (f is null)
        return -1;
    f.used = false;
    return 0;
}

/// Read up to `len` bytes into `dst` (kernel or already validated user memory).
/// Returns the byte count, 0 at the end of the file, -1 on error.
long sysfileRead(ulong fd, void* dst, ulong len) @nogc nothrow
{
    OpenFile* f = sysfileGet(fd);
    if (f is null || f.isDir)
        return -1;
    if (f.pos >= f.entry.size || len == 0)
        return 0;
    if (len > f.entry.size - f.pos)
        len = f.entry.size - f.pos;
    if (len > 1024 * 1024)
        len = 1024 * 1024;

    ulong got = exfatRead(&rootMount.vol, &f.file, f.pos, dst, len);
    if (got == 0)
        return -1;
    f.pos += got;
    return cast(long)got;
}

/// whence: 0 = from the start, 1 = from the current position, 2 = from the end.
/// Returns the new position or -1. Seeking past the end is allowed (reads return 0).
long sysfileSeek(ulong fd, long offset, ulong whence) @nogc nothrow
{
    OpenFile* f = sysfileGet(fd);
    if (f is null || f.isDir)
        return -1;
    long base;
    if (whence == 0)
        base = 0;
    else if (whence == 1)
        base = cast(long)f.pos;
    else if (whence == 2)
        base = cast(long)f.entry.size;
    else
        return -1;
    long target = base + offset;
    if (target < 0)
        return -1;
    f.pos = cast(ulong)target;
    return target;
}

bool sysfileStat(const(char)* path, UserStat* st) @nogc nothrow
{
    ExfatEntry e;
    if (!fsStat(path, &e))
        return false;
    st.size = e.size;
    st.mtime = e.mtime;
    st.isDir = e.isDir ? 1 : 0;
    return true;
}

extern(C) bool sysfilePickCb(const(ExfatEntry)* e, void* ctx) @nogc nothrow
{
    DirPick* p = cast(DirPick*)ctx;
    if (p.seen == p.want)
    {
        p.entry = *e;
        p.found = true;
        return false;
    }
    p.seen++;
    return true;
}

/// Next entry of an open directory. 1 = filled in, 0 = no more, -1 = error.
long sysfileReaddir(ulong fd, UserDirent* out_) @nogc nothrow
{
    OpenFile* f = sysfileGet(fd);
    if (f is null || !f.isDir)
        return -1;

    DirPick pick;
    pick.want = f.pos;
    if (!exfatIterate(&rootMount.vol, &f.entry, &sysfilePickCb, &pick))
        return -1;
    if (!pick.found)
        return 0;

    f.pos++;
    out_.size = pick.entry.size;
    out_.mtime = pick.entry.mtime;
    out_.isDir = pick.entry.isDir ? 1 : 0;
    for (uint i = 0; i < EXFAT_NAME_MAX; i++)
        out_.name[i] = pick.entry.name[i];
    return 1;
}

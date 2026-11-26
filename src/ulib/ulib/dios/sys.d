/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/
module ulib.dios.sys;

import ulib.dios.io;

/**
 * DIOS kernel API
 */

// System calls group 1 (0..99): process and memory management
enum ulong SYS_GROUP1   = 0;
enum ulong SYS_EXIT     = SYS_GROUP1 + 0;
enum ulong SYS_WRITE    = SYS_GROUP1 + 1;
enum ulong SYS_GETKEY   = SYS_GROUP1 + 2;
enum ulong SYS_SLEEP    = SYS_GROUP1 + 3;
enum ulong SYS_TICKS    = SYS_GROUP1 + 4;
enum ulong SYS_CLEAR    = SYS_GROUP1 + 5;
enum ulong SYS_BRK      = SYS_GROUP1 + 6;
enum ulong SYS_YIELD    = SYS_GROUP1 + 7;
enum ulong SYS_GETPID   = SYS_GROUP1 + 8;
enum ulong SYS_DATETIME = SYS_GROUP1 + 9;
enum ulong SYS_RANDOM   = SYS_GROUP1 + 10;
enum ulong SYS_SPAWN    = SYS_GROUP1 + 11;
enum ulong SYS_STR      = SYS_GROUP1 + 12;

// System calls group 2 (100..199): filesystem
enum ulong SYS_GROUP2   = 100;
enum ulong SYS_OPEN     = SYS_GROUP2 + 0;
enum ulong SYS_READ     = SYS_GROUP2 + 1;
enum ulong SYS_FWRITE   = SYS_GROUP2 + 2;
enum ulong SYS_CLOSE    = SYS_GROUP2 + 3;
enum ulong SYS_SEEK     = SYS_GROUP2 + 4;
enum ulong SYS_STAT     = SYS_GROUP2 + 5;
enum ulong SYS_READDIR  = SYS_GROUP2 + 6;
enum ulong SYS_GETCWD   = SYS_GROUP2 + 7;
enum ulong SYS_UNLINK   = SYS_GROUP2 + 8;
enum ulong SYS_MKDIR    = SYS_GROUP2 + 9;
enum ulong SYS_RMDIR    = SYS_GROUP2 + 10;
enum ulong SYS_RENAME   = SYS_GROUP2 + 11;
enum ulong SYS_SYNC     = SYS_GROUP2 + 12;
enum ulong SYS_CHDIR    = SYS_GROUP2 + 13;
enum ulong SYS_REALPATH = SYS_GROUP2 + 14;

// System calls group 3 (200-299): stdout/channel control
enum ulong SYS_GROUP3     = 200;
enum ulong SYS_CH_CREATE = SYS_GROUP3 + 0;
enum ulong SYS_CH_READ   = SYS_GROUP3 + 1;
enum ulong SYS_CH_STAT   = SYS_GROUP3 + 2;
enum ulong SYS_CH_CLOSE  = SYS_GROUP3 + 3;

// System calls group 4 (300-399): reserved
enum ulong SYS_GROUP4     = 300;

// System calls group 5 (400-499): reserved
enum ulong SYS_GROUP5     = 400;

// System calls group 6 (500-599): reserved
enum ulong SYS_GROUP6     = 500;

// System calls group 7 (600-699): reserved
enum ulong SYS_GROUP7     = 600;

// System calls group 8 (700-799): reserved
enum ulong SYS_GROUP8     = 700;

// System calls group 9 (800-899): reserved
enum ulong SYS_GROUP9     = 800;

// System calls group 10 (900-999): reserved
enum ulong SYS_GROUP10    = 900;

// Extended system calls
enum ulong SYS_EXT1     = 1000; // Graphics server
enum ulong SYS_EXT2     = 2000; // Reserved
enum ulong SYS_EXT3     = 3000; // Reserved
enum ulong SYS_EXT4     = 4000; // Reserved

// Recognized by SYS_STR
enum uint SYS_STR_VERSION = 0;
enum uint SYS_STR_ABOUT   = 1;

// Standard output targets for uspawn()
enum uint STDOUT_CONSOLE = 0;           // the kernel console (what the kernel shell shows)
enum uint STDOUT_INHERIT = 0xFFFFFFFF;  // wherever the spawning program writes itself

// uopen() flags
enum int O_RDONLY = 0;
enum int O_WRONLY = 1;
enum int O_RDWR   = 2;
// Combine with O_WRONLY or O_RDWR. Writing works on FAT32 volumes mounted with "rw" (shell: mount N NAME rw).
enum int O_CREATE = 0x40;   // create the file if it does not exist
enum int O_TRUNC  = 0x200;  // make it empty
enum int O_APPEND = 0x400;  // every write goes to the end

// Error codes returned (negated) by the file system calls that change things
enum int UERR_IO = -1;
enum int UERR_NOT_FOUND = -2;
enum int UERR_EXISTS = -3;
enum int UERR_NO_SPACE = -4;
enum int UERR_BAD_NAME = -5;
enum int UERR_NOT_EMPTY = -6;
enum int UERR_IS_DIR = -7;
enum int UERR_NOT_DIR = -8;
enum int UERR_READ_ONLY = -9;
enum int UERR_INVALID = -10;

struct DateTime
{
    ushort year;
    ubyte month;
    ubyte day;
    ubyte weekday;
    ubyte hour;
    ubyte minute;
    ubyte second;
}

// useek() origins
enum int SEEK_SET = 0;
enum int SEEK_CUR = 1;
enum int SEEK_END = 2;

struct UStat
{
    ulong size;
    uint mtime; // DOS timestamp: (year-1980)<<25 | month<<21 | day<<16 | hour<<11 | min<<5 | sec/2
    uint isDir;
}

struct UDirent
{
    ulong size;
    uint mtime;
    uint isDir;
    char[256] name;
}

// Key codes returned by getkey (besides plain ASCII; Enter is 10).
enum int KEY_UP = 0x101;
enum int KEY_DOWN = 0x102;
enum int KEY_LEFT = 0x103;
enum int KEY_RIGHT = 0x104;
enum int KEY_HOME = 0x105;
enum int KEY_END = 0x106;
enum int KEY_DELETE = 0x107;

extern(C):

/// Calls a kernel function. Implemented in assembly (sys.s)
long sys_call(ulong nr, ulong a0, ulong a1, ulong a2) @nogc nothrow;

/// Terminates the application.
void uexit(long code) @nogc nothrow
{
    uflush_b(); // flush the output
    sys_call(SYS_EXIT, cast(ulong)code, 0, 0);
}

/**
 * Writes to the standard output. Where that is depends on how the program was started:
 * the kernel console (the kernel shell) by default, or a channel read by a terminal
 * program (see uttyCreate / uspawn). Blocks while a channel's buffer is full.
 */
void uwrite(const(char)* s, size_t n) @nogc nothrow
{
    sys_call(SYS_WRITE, cast(ulong)s, n, 0);
}

/// Next key (ASCII, Enter = 10, or KEY_*). With block == false returns -1 if none is waiting.
int ugetkey(bool block) @nogc nothrow
{
    return cast(int)sys_call(SYS_GETKEY, block ? 1 : 0, 0, 0);
}

/// Stops execution for a given time in milliseconds.
void usleep(ulong ms) @nogc nothrow
{
    sys_call(SYS_SLEEP, ms, 0, 0);
}

/// Returns the number of millisecond ticks since the system start.
ulong uticks() @nogc nothrow
{
    return cast(ulong)sys_call(SYS_TICKS, 0, 0, 0);
}

/// Let other programs run now.
void uyield() @nogc nothrow
{
    sys_call(SYS_YIELD, 0, 0, 0);
}

/// Task id of this program (as shown by `ps`).
int ugetpid() @nogc nothrow
{
    return cast(int)sys_call(SYS_GETPID, 0, 0, 0);
}

/// Clears the standard output. On a terminal channel this sends a form feed (12) and the terminal decides what it does.
void uclear() @nogc nothrow
{
    sys_call(SYS_CLEAR, 0, 0, 0);
}

// Files. Reading works everywhere; writing only on FAT32 volumes mounted with "rw". Paths are relative to the shell's current directory or absolute.
// At most 8 files can be open at once; they are closed when the program ends.

/**
 * Returns the file descriptor of a file or directory, or a negative UERR_* code (UERR_NOT_FOUND,
 * UERR_READ_ONLY, UERR_BAD_NAME, ...) if it doesn't exist or cannot be opened that way. flag is O_RDONLY (0), or O_WRONLY / O_RDWR optionally with O_CREATE,
 * O_TRUNC and O_APPEND. Directories can only be opened with O_RDONLY.
 */
int uopen(const(char)* path, int flag) @nogc nothrow
{
    return cast(int)sys_call(SYS_OPEN, cast(ulong)path, cast(ulong)flag, 0);
}

/// Reads bytes from the file at the current offset. Returns the number of bytes read (0 = end of file), or -1 on error.
long uread(int fd, void* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_READ, cast(ulong)fd, cast(ulong)buf, n);
}

/// Closes the file.
int uclose(int fd) @nogc nothrow
{
    return cast(int)sys_call(SYS_CLOSE, cast(ulong)fd, 0, 0);
}

/// Jumps to a byte offset in the file. Returns a new position, or -1 on error.
long useek(int fd, long offset, int whence) @nogc nothrow
{
    return sys_call(SYS_SEEK, cast(ulong)fd, cast(ulong)offset, cast(ulong)whence);
}

/// Retrieves file stats. Returns 0 on success, -1 if the path does not exist.
int ustat(const(char)* path, UStat* st) @nogc nothrow
{
    return cast(int)sys_call(SYS_STAT, cast(ulong)path, cast(ulong)st, 0);
}

/// Fills the next entry of a directory opened with uopen(). Returns 1 if filled in, 0 if there are no more entries, -1 on error.
int ureaddir(int fd, UDirent* e) @nogc nothrow
{
    return cast(int)sys_call(SYS_READDIR, cast(ulong)fd, cast(ulong)e, 0);
}

/// Writes the current working directory into a provided character buffer. Returns CWD length or -1 on error.
long ugetcwd(char* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_GETCWD, cast(ulong)buf, n, 0);
}

/**
 * Query or change the current process' heap break.
 * If `newBreak` is null, queries the current break; otherwise sets the break to requested.
 * Returns the current/new break, or null on error.
 */
void* ubrk(void* newBreak) @nogc nothrow
{
    long result = sys_call(SYS_BRK, cast(ulong)newBreak, 0, 0);
    return result < 0 ? null : cast(void*)result;
}

/// Retrieves the current UTC date-time.
void udatetime(DateTime* dt) @nogc nothrow
{
    sys_call(SYS_DATETIME, cast(ulong)dt, 0, 0);
}

/// 
void urandom(void* buffer, size_t size) @nogc nothrow
{
    sys_call(SYS_RANDOM, cast(ulong)buffer, size, 0);
}

/**
 * Starts the ELF file `path` (exact path; no search, no ".elf" added) as a background program.
 * `args` is its argument string (or null). `stdoutTarget` is where its uwrite()/uprintf() output goes:
 * STDOUT_CONSOLE, STDOUT_INHERIT, or a channel from uttyCreate() (that you read, or that you write to yourself).
 * Returns the task id of the new program (as shown by `ps`), or -1.
 */
int uspawn(const(char)* path, const(char)* args, uint stdoutTarget) @nogc nothrow
{
    return cast(int)sys_call(SYS_SPAWN, cast(ulong)path, cast(ulong)args, cast(ulong)stdoutTarget);
}

/**
 * Retrieves a system info string to a given buffer.
 * Returns the number of characters written, or -1 on error.
 * `strid` is the system info string identifier:
 * - `SYS_STR_VERSION` - the operating system version
 * - `SYS_STR_ABOUT` - extended information about the operating system
 */
long usysstr(char* buf, size_t size, uint strid) @nogc nothrow
{
    return cast(int)sys_call(SYS_STR, cast(ulong)buf, size, strid);
}

/**
 * Writes bytes to a file opened with O_WRONLY or O_RDWR, at the current offset (the end with
 * O_APPEND). Returns the number of bytes written (fewer if the volume is full), or -1 on error.
 * The data is on the disk when the call returns.
 */
long ufwrite(int fd, const(void)* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_FWRITE, cast(ulong)fd, cast(ulong)buf, n);
}

/// Deletes a file. Returns 0 or a negative UERR_* code.
int uunlink(const(char)* path) @nogc nothrow
{
    return cast(int)sys_call(SYS_UNLINK, cast(ulong)path, 0, 0);
}

/// Creates a directory. Returns 0 or a negative UERR_* code.
int umkdir(const(char)* path) @nogc nothrow
{
    return cast(int)sys_call(SYS_MKDIR, cast(ulong)path, 0, 0);
}

/// Removes an empty directory. Returns 0 or a negative UERR_* code.
int urmdir(const(char)* path) @nogc nothrow
{
    return cast(int)sys_call(SYS_RMDIR, cast(ulong)path, 0, 0);
}

/**
 * Renames or moves a file or directory within one volume; the new name must not exist.
 * Returns 0 or a negative UERR_* code.
 */
int urename(const(char)* from, const(char)* to) @nogc nothrow
{
    return cast(int)sys_call(SYS_RENAME, cast(ulong)from, cast(ulong)to, 0);
}

/**
 * Changes the current directory of this program. Every program has its own: it starts in the directory
 * of the program that started it, and changing it affects nobody else (so a separate `cd` program
 * cannot exist; a shell does it itself). Returns 0 or a negative UERR_* code (UERR_NOT_FOUND, UERR_NOT_DIR).
 */
int uchdir(const(char)* path) @nogc nothrow
{
    return cast(int)sys_call(SYS_CHDIR, cast(ulong)path, 0, 0);
}

/**
 * Writes the absolute, normalised form of `path` (relative paths start at the current directory; "." and ".."
 * are resolved) to `buf`. The file does not have to exist. Returns its length, or -1 if it does not fit.
 */
long urealpath(const(char)* path, char* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_REALPATH, cast(ulong)path, cast(ulong)buf, n);
}

/// Text for a negative UERR_* code returned by the file system calls.
const(char)* uerrstr(int err) @nogc nothrow
{
    switch (err)
    {
        case UERR_IO: return "I/O error";
        case UERR_NOT_FOUND: return "not found";
        case UERR_EXISTS: return "already exists";
        case UERR_NO_SPACE: return "no space left on the volume";
        case UERR_BAD_NAME: return "invalid name (ASCII only, no \\ / : * ? \" < > |)";
        case UERR_NOT_EMPTY: return "directory not empty";
        case UERR_IS_DIR: return "is a directory";
        case UERR_NOT_DIR: return "not a directory";
        case UERR_READ_ONLY: return "read-only (only /home and FAT32 volumes mounted with 'rw' can be changed)";
        default: return "invalid operation";
    }
}

/// Prints "what: path: reason" for a UERR_* code (to the standard output, like the other messages of the programs).
void uperror(const(char)* what, const(char)* path, int err) @nogc nothrow
{
    uprintf("%s: %s: %s\n", what, path, uerrstr(err));
}

/**
 * For cp and mv: if `dst` is an existing directory, `out_` becomes "dst/name-of-src", otherwise a copy of `dst`.
 * `out_` has room for `cap` bytes.
 */
void utargetpath(const(char)* src, const(char)* dst, char* out_, size_t cap) @nogc nothrow
{
    size_t n = 0;
    while (dst[n] != 0 && n + 1 < cap)
    {
        out_[n] = dst[n];
        n++;
    }
    out_[n] = 0;

    UStat st;
    if (ustat(dst, &st) < 0 || !st.isDir)
        return;

    size_t base = 0;
    for (size_t s = 0; src[s] != 0; s++)
        if (src[s] == '/' && src[s + 1] != 0)
            base = s + 1;
    if (n > 0 && out_[n - 1] != '/' && n + 1 < cap)
        out_[n++] = '/';
    while (src[base] != 0 && src[base] != '/' && n + 1 < cap)
        out_[n++] = src[base++];
    out_[n] = 0;
}

/// Asks the disks to put everything they hold on the medium.
void usync() @nogc nothrow
{
    sys_call(SYS_SYNC, 0, 0, 0);
}

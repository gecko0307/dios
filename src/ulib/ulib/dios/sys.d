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

// Kernel function numbers
enum ulong SYS_EXIT = 0;
enum ulong SYS_WRITE = 1;
enum ulong SYS_GETKEY = 2;
enum ulong SYS_SLEEP = 3;
enum ulong SYS_TICKS = 4;
enum ulong SYS_CLEAR = 5;
enum ulong SYS_OPEN = 6;
enum ulong SYS_READ = 7;
enum ulong SYS_CLOSE = 8;
enum ulong SYS_SEEK = 9;
enum ulong SYS_STAT = 10;
enum ulong SYS_READDIR = 11;
enum ulong SYS_GETCWD = 12;
enum ulong SYS_BRK = 13;
enum ulong SYS_YIELD = 14;
enum ulong SYS_GETPID = 15;
enum ulong SYS_DATETIME = 16;
enum ulong SYS_RANDOM = 17;

// uopen() flags
enum int O_RDONLY = 0;
enum int O_WRONLY = 1;
enum int O_RDWR   = 2;

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

extern(C):

/// Calls a kernel function. Implemented in assembly (sys.s)
long sys_call(ulong nr, ulong a0, ulong a1, ulong a2) @nogc nothrow;

/// Terminates the application.
void uexit(long code) @nogc nothrow
{
    uflush_b(); // flush the output
    sys_call(SYS_EXIT, cast(ulong)code, 0, 0);
}

/// Writes to the standard output (the kernel shell, if running in text mode).
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

/// Clears the standard ouput (the kernel shell, if running in text mode).
void uclear() @nogc nothrow
{
    sys_call(SYS_CLEAR, 0, 0, 0);
}

// Files (read-only). Paths are relative to the shell's current directory or absolute.
// At most 8 files can be open at once; they are closed when the program ends.

/**
 * Returns the file descriptor of a file or directory, or -1 if it doesn't exist.
 * flag parameters is currently not used and should be zero (O_RDONLY).
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
